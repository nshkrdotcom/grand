defmodule Grand.Assurance.G05VerificationTest do
  use ExUnit.Case, async: false

  alias Grand.Assurance.G03
  alias Grand.Assurance.G04.Runner
  alias Grand.Assurance.G05
  alias Grand.Assurance.G05.{Impact, Lynx, Veil}
  alias Grand.Core.JSON

  @fixtures Path.expand("../../../fixtures", __DIR__)
  @g05 Path.join(@fixtures, "g05")
  @at "2026-11-06T20:00:00Z"
  @review [actor: "human:fixture-reviewer", at: @at, ack_human: true]

  setup do
    root =
      Path.join(System.tmp_dir!(), "grand-g05-assurance-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp json(path) do
    {:ok, data} = JSON.decode(File.read!(path))
    data
  end

  defp manifest(name) do
    input = json(Path.join(@g05, "#{name}-manifest.json"))

    case input do
      %{"law" => law} ->
        updated =
          Enum.reduce(~w(file source_file support_file), law, fn key, acc ->
            Map.update!(acc, key, &Path.join(@g05, &1))
          end)

        %{input | "law" => updated}

      %{"model" => model} ->
        put_in(input, ["model", "file"], Path.join(@g05, model["file"]))
    end
  end

  defp approved(root) do
    resolver = fn _ -> {:ok, %{"source_only" => true}} end
    opts = @review ++ [resolve_source: resolver]

    for kind <- ~w(assumption) do
      assert {:ok, _} =
               G03.register_assumption(
                 root,
                 json(Path.join(@fixtures, "g03_#{kind}_input.json")),
                 opts
               )
    end

    assert {:ok, draft} =
             G03.draft_requirement(
               root,
               json(Path.join(@fixtures, "g03_requirement_input.json")),
               opts
             )

    assert {:ok, _} = G03.review_requirement(root, draft["id"], "submit", opts)
    assert {:ok, _} = G03.review_requirement(root, draft["id"], "approve", opts)

    assert {:ok, _} =
             G03.record_obligation(
               root,
               json(Path.join(@fixtures, "g03_obligation_input.json")),
               opts
             )
  end

  test "G05-TEST-01..05 source-only v1 snapshot and Hold mutation with reverse links" do
    before = json(Path.join(@g05, "impact/before.json"))
    links = json(Path.join(@g05, "impact/links.json"))["links"]
    assert {:ok, same} = Impact.compare(before, before, links)
    assert same["evidence_status"] == "unaffected"
    assert same["changes"] == []

    bad = json(Path.join(@g05, "impact/premature.json"))
    assert {:ok, changed} = Impact.compare(before, bad, links)
    assert changed["evidence_status"] == "stale"
    assert changed["affected_requirements"] == ["g03-confirm-once"]
    assert changed["affected_obligations"] == ["g03-obligation-once"]
    assert changed["affected_results"] == ["fixture:g05-law-requires-recheck"]
    assert changed["changes"] |> Enum.any?(&(&1["kind"] == "modified"))
    assert Map.has_key?(changed["reverse_links"], "hold:void-request")
    assert changed["classification"] =~ "syntactic_source_only"

    missing = json(Path.join(@g05, "impact/effect-omitted.json"))
    assert {:ok, loss} = Impact.compare(before, missing, links)
    assert loss["evidence_status"] == "unresolved"
    assert "hold:void-effect" in loss["unresolved_mappings"]

    moved = json(Path.join(@g05, "impact/line-shift.json"))
    assert {:ok, shift} = Impact.compare(before, moved, links)
    assert shift["evidence_status"] == "unresolved"
    assert "hold:void-request" in shift["unresolved_mappings"]
  end

  test "G05-TEST-01/05 v2 syntactic mapping never invents semantic equivalence" do
    before = json(Path.join(@g05, "impact/v2-before.json"))
    after_snapshot = json(Path.join(@g05, "impact/v2-line-shift.json"))
    assert {:ok, result} = Impact.compare(before, after_snapshot, [])
    assert result["upstream_schema_version"] == 2
    assert Enum.any?(result["probable_matches"], &(&1["confidence"] == "probable_not_verified"))

    assert {:error, :unsupported_upstream_version} =
             Impact.compare(%{before | "schema_version" => 99}, before, [])

    assert {:error, :different_or_invalid_snapshot_versions} =
             Impact.compare(before, json(Path.join(@g05, "impact/before.json")), [])
  end

  test "G05-TEST-01..05 actual pinned source exports and evidence-to-source reverse closure" do
    before = json(Path.join(@fixtures, "upstream/beamcompass-p02b/a.json"))
    later = json(Path.join(@fixtures, "upstream/beamcompass-p02b/mutated.json"))

    assert {:ok, %{"changes" => [], "evidence_status" => "unaffected"}} =
             Impact.compare(before, before, [])

    assert {:ok, report} = Impact.compare(before, later, [])
    assert report["classification"] =~ "source_only"
    assert report["evidence_status"] == "unresolved"
    observed = put_in(before, ["manifest", "providers", Access.at(0), "mode"], "runtime")
    assert {:error, :invalid_source_only_snapshot} = Impact.compare(observed, before, [])
    altered = put_in(before, ["manifest", "toolchain", "elixir"], "changed")
    assert {:ok, %{"evidence_status" => "unresolved"}} = Impact.compare(before, altered, [])
    original = json(Path.join(@g05, "impact/v2-before.json"))
    [entity] = original["entities"]
    [evidence] = original["evidence"]
    mutated = put_in(original, ["evidence"], [Map.put(evidence, "kind", "changed_source")])

    link = %{
      "source_refs" => [%{"object_id" => entity["id"]}],
      "requirement" => %{"id" => "req", "revision" => 1},
      "obligation_id" => "ob",
      "result_ids" => ["run"],
      "assumptions" => [],
      "model_files" => []
    }

    assert {:ok, %{"affected_results" => ["run"], "evidence_status" => "stale"}} =
             Impact.compare(original, mutated, [link])
  end

  test "G05-TEST-06 law is bound to original source and the mutant changes the code input", %{
    root: root
  } do
    approved(root)
    good = manifest("lynx-good")
    bad = manifest("lynx-bad")
    assert {:ok, original} = G05.run(root, good)
    assert original["status"] == "unrun"
    assert original["engine"] == "lynx"
    assert original["qualifications"]["kind"] == "lynx_translated_beam_law"
    assert original["qualifications"]["open_axiom_gap"] == true

    assert original["inputs"]["source_files"]["source"]["sha256"] !=
             (G05.run(root, bad) |> elem(1))["inputs"]["source_files"]["source"]["sha256"]
  end

  test "G05-TEST-07 exact G03 obligations, no implicit law execution, stale source/tool", %{
    root: root
  } do
    approved(root)
    manifest = manifest("lynx-good")
    assert {:ok, original} = G05.run(root, manifest)
    assert {:ok, %{"applicability" => "current"}} = G05.applicability(original, root, manifest)
    assert {:ok, mutation} = G05.applicability(original, root, manifest("lynx-bad"))
    assert mutation["applicability"] == "stale"
    assert "source_files" in mutation["reasons"]

    assert {:error, :explicit_law_code_permission_required} =
             G05.run(root, manifest, execute: true)

    invalid = put_in(manifest, ["assumptions"], [])
    assert {:error, :g05_assumption_revision_mismatch} = G05.run(root, invalid)
    invalid = put_in(manifest, ["source_refs"], [])
    assert {:error, :g05_source_scope_mismatch} = G05.run(root, invalid)
    invalid = put_in(manifest, ["requirement", "revision"], 123)
    assert {:error, :g05_requirement_revision_mismatch} = G05.run(root, invalid)

    altered_tool = put_in(original, ["inputs", "tool", "available"], "changed")
    assert {:ok, stale} = G05.applicability(altered_tool, root, manifest)
    assert "tool" in stale["reasons"]

    changed_support =
      put_in(manifest, ["law", "support_file"], Path.join(@g05, "lynx/SourcePremature.ex"))

    assert {:ok, %{"applicability" => "stale", "reasons" => support_reasons}} =
             G05.applicability(original, root, changed_support)

    assert "source_files" in support_reasons

    revised_manifest = put_in(manifest, ["law", "origin"], "changed original-law origin")

    assert {:ok, %{"applicability" => "stale", "reasons" => manifest_reasons}} =
             G05.applicability(original, root, revised_manifest)

    assert "manifest" in manifest_reasons

    changed_assumptions = put_in(original, ["inputs", "assumption_revisions"], [])

    assert {:ok, %{"applicability" => "stale", "reasons" => assumption_reasons}} =
             G05.applicability(changed_assumptions, root, manifest)

    assert "assumption_revisions" in assumption_reasons

    assert {:ok, historical} = G03.receipt(root, manifest["obligation_id"])
    assert historical["verification_result"]["status"] == "unrun"
  end

  test "G05-TEST-07 allowlisted plans deny arbitrary code and substitution" do
    for plan <- [
          %{"engine" => "elixir", "args" => ["-e", "IO.puts(:forged)"], "files" => %{}},
          %{"engine" => "lake", "args" => ["exe", "malicious"], "files" => %{}},
          %{"engine" => "elixir", "args" => ["Verify.exs"], "files" => %{"../escape" => "x"}}
        ] do
      assert {:error, :unsafe_runner_plan} = Runner.execute(plan, execute: true)
    end

    assert {:error, :unsafe_runner_policy} =
             Runner.execute(%{"engine" => "lean", "args" => ["--version"], "files" => %{}},
               execute: true,
               timeout_ms: -1
             )
  end

  test "G05-TEST-07 forged parser markers are not proof or Veil outcomes" do
    manifest = manifest("lynx-good")
    assert {:ok, plan} = Lynx.prepare(manifest, [])

    forged = %{
      "stdout" => "GRAND_LYNX_REPORT_V1:{\"status\":\"ok\"}\n",
      "stderr" => "",
      "exit_code" => 0,
      "reason" => nil,
      "artifacts" => %{"proof_export" => false}
    }

    assert {:ok, %{"status" => "error"}} = Lynx.normalize(plan, forged)
    assert {:ok, veil_plan} = Veil.prepare(manifest("veil-safe"), [])

    assert {:ok, %{"status" => "inconclusive"}} =
             Veil.normalize(veil_plan, %{
               "reason" => nil,
               "exit_code" => 0,
               "stdout" => "file elaborated",
               "stderr" => ""
             })
  end

  test "G05-TEST-08 Veil explicit-state paths remain unrun without engines", %{root: root} do
    approved(root)
    assert {:ok, good} = G05.run(root, manifest("veil-safe"))
    assert good["status"] == "unrun"
    assert good["qualifications"]["solver"] == "none_for_explicit_state"
    assert good["qualifications"]["finite_exploration_not_unbounded_proof"] == true
    assert {:ok, changed} = G05.applicability(good, root, manifest("veil-bad"))
    assert "source_files" in changed["reasons"]

    assert {:error, :explicit_law_code_permission_required} =
             G05.run(root, manifest("veil-safe"), execute: true)
  end

  test "G05-TEST-09 actual requirement and assumption revisions stale prior evidence", %{
    root: root
  } do
    approved(root)
    input = manifest("lynx-good")
    assert {:ok, old} = G05.run(root, input)
    assert {:ok, _} = G03.revise_assumption(root, "g03-external-dedup", "attest", @review)

    assert {:ok, %{"applicability" => "stale", "reasons" => reasons}} =
             G05.applicability(old, root, input)

    assert "assumption_revisions" in reasons

    replacement =
      json(Path.join(@fixtures, "g03_requirement_input.json"))
      |> Map.put("id", "g05-review-required")

    assert {:ok, _} =
             G03.draft_requirement(
               root,
               replacement,
               @review ++ [resolve_source: fn _ -> {:ok, %{"source_only" => true}} end]
             )

    for action <- ~w(submit approve) do
      assert {:ok, _} =
               G03.review_requirement(
                 root,
                 "g05-review-required",
                 action,
                 @review ++ [resolve_source: fn _ -> {:ok, %{"source_only" => true}} end]
               )
    end

    assert {:ok, _} =
             G03.review_requirement(
               root,
               "g03-confirm-once",
               "supersede",
               @review ++
                 [
                   replacement_id: "g05-review-required",
                   resolve_source: fn _ -> {:ok, %{"source_only" => true}} end
                 ]
             )

    assert {:ok, %{"applicability" => "stale", "reasons" => reasons}} =
             G05.applicability(old, root, input)

    assert "requirement" in reasons
  end

  test "G05-TEST-07 missing tools and invalid version/extra worker keys fail closed", %{
    root: root
  } do
    approved(root)

    for name <- ~w(lynx-good veil-safe) do
      input = manifest(name)

      assert {:ok, %{"status" => "unsupported"}} =
               G05.run(root, input, execute: true, allow_law_code: true, tool_root: root)

      assert {:ok, %{"status" => "unrun"}} = G05.run(root, input, allow_law_code: true)
      assert {:error, :invalid_g05_manifest} = G05.run(root, Map.put(input, "schema_version", 99))

      assert {:error, :invalid_g05_manifest} =
               G05.run(root, Map.put(input, "allow_law_code", true))

      assert {:error, :invalid_g05_manifest} = G05.run(root, Map.put(input, "unexpected", %{}))
    end
  end

  test "G05-TEST-07 forged or contradictory Veil outcomes and depth overrides are rejected", %{
    root: root
  } do
    input = manifest("veil-safe")
    assert {:ok, plan} = Veil.prepare(input, [])

    for output <- [
          "No violation (explored 0 states)",
          "No violation (explored 3 states)\nViolation: safety_failure (violates: other)",
          "Violation: safety_failure (violates: no_premature_release)"
        ] do
      assert {:ok, result} =
               Veil.normalize(plan, %{
                 "reason" => nil,
                 "exit_code" => 0,
                 "stdout" => output,
                 "stderr" => ""
               })

      refute result["status"] in ~w(bounded_pass counterexample)
    end

    source = File.read!(input["model"]["file"])

    for injected <- [
          "\n#eval IO.println(\"No violation (explored 3 states)\")\n",
          "\nset_option veil.modelChecker.maxDepth 1\n"
        ] do
      path = Path.join(root, "forged.lean")
      File.write!(path, source <> injected)
      assert {:error, _} = Veil.prepare(put_in(input, ["model", "file"], path), [])
    end
  end

  test "G05-TEST-07 new worker stream caps, staged permissions and artifact bound", %{root: root} do
    bin = Path.join(root, "bin")
    File.mkdir_p!(bin)
    tool = Path.join(bin, "elixir")
    {:ok, plan} = Lynx.prepare(manifest("lynx-good"), [])
    plan = %{plan | "args" => ["-pa", "/trusted/_build/dev/lib/lynx/ebin", "Verify.exs"]}
    previous = System.get_env("PATH") || ""

    try do
      System.put_env("PATH", bin <> ":" <> previous)
      File.write!(tool, "#!/bin/sh\nstat -c %a Source.ex; printf 'err' >&2\n")
      File.chmod!(tool, 0o755)
      assert {:ok, raw} = Runner.execute(plan, execute: true)
      assert raw["stdout"] == "600\n"
      assert raw["stderr"] == "err"

      for fd <- ["", " >&2"] do
        File.write!(tool, "#!/bin/sh\nprintf '%800s' x#{fd}\n")

        assert {:ok, %{"reason" => "output_limit"}} =
                 Runner.execute(plan, execute: true, output_limit_bytes: 256)
      end

      File.write!(tool, "#!/bin/sh\ntruncate -s 65000000 generated.bin\n")
      assert {:ok, %{"reason" => "artifact_limit"}} = Runner.execute(plan, execute: true)
    after
      System.put_env("PATH", previous)
    end
  end

  @tag timeout: 180_000
  test "G05-TEST-06/08 real installed Lynx and Veil acceptance is conditional, never faked", %{
    root: root
  } do
    approved(root)

    if System.get_env("GRAND_RUN_G05_ENGINES") == "1" do
      for {name, expected} <- [
            {"lynx-good", "proved"},
            {"lynx-bad", "error"},
            {"veil-safe", "bounded_pass"},
            {"veil-bad", "counterexample"}
          ] do
        assert {:ok, result} =
                 G05.run(root, manifest(name),
                   execute: true,
                   allow_law_code: true,
                   timeout_ms: 60_000
                 )

        assert result["status"] == expected,
               "real backend #{name}: #{inspect(Map.take(result, ~w(diagnostics stdout stderr runner)))}"
      end
    else
      for name <- ~w(lynx-good lynx-bad veil-safe veil-bad) do
        assert {:ok, %{"status" => "unrun"}} = G05.run(root, manifest(name))
      end
    end
  end
end
