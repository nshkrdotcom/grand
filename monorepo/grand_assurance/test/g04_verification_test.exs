defmodule Grand.Assurance.G04Test do
  use ExUnit.Case, async: false

  alias Grand.Assurance.G03
  alias Grand.Assurance.G04
  alias Grand.Assurance.G04.Files
  alias Grand.Assurance.G04.Lean
  alias Grand.Assurance.G04.Runner
  alias Grand.Assurance.G04.TLC
  alias Grand.Core.JSON

  @fixtures Path.expand("../../../fixtures", __DIR__)
  @g04 Path.join(@fixtures, "g04")
  @at "2026-11-06T20:00:00Z"
  @review [actor: "human:fixture-reviewer", at: @at, ack_human: true]

  setup do
    root =
      Path.join(System.tmp_dir!(), "grand-g04-assurance-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp json(path) do
    {:ok, content} = JSON.decode(File.read!(path))
    content
  end

  defp fixture(kind), do: json(Path.join(@fixtures, "g03_#{kind}_input.json"))

  defp manifest(name) do
    data = json(Path.join(@g04, "#{name}-manifest.json"))

    case data do
      %{"law" => law} ->
        put_in(data, ["law", "file"], Path.join(@g04, law["file"]))

      %{"model" => model} ->
        data
        |> put_in(["model", "file"], Path.join(@g04, model["file"]))
        |> put_in(["model", "config_file"], Path.join(@g04, model["config_file"]))
    end
  end

  defp approved(root) do
    resolver = fn _ -> {:ok, %{"source_only" => true}} end
    opts = @review ++ [resolve_source: resolver]
    {:ok, _} = G03.register_assumption(root, fixture("assumption"), opts)
    {:ok, draft} = G03.draft_requirement(root, fixture("requirement"), opts)
    {:ok, _} = G03.review_requirement(root, draft["id"], "submit", opts)
    {:ok, _} = G03.review_requirement(root, draft["id"], "approve", opts)
    {:ok, obligation} = G03.record_obligation(root, fixture("obligation"), opts)
    {opts, obligation}
  end

  test "G04-TEST-01 Lean law path stays unrun until separately authorized", %{root: root} do
    {_opts, obligation} = approved(root)
    assert {:ok, data} = G04.run(root, manifest("lean"))
    assert data["status"] == "unrun"
    assert data["engine"] == "lean"
    assert data["qualifications"]["lynx_law_bundle_qualified"] == false
    assert data["inputs"]["obligation"]["id"] == obligation["id"]
    assert data["assumption_revisions"] != []
    assert data["witness_challenge"]["status"] == "missing"
    assert {:ok, historical} = G03.receipt(root, obligation["id"])
    assert historical["verification_result"]["status"] == "unrun"

    assert {:error, :explicit_law_code_permission_required} =
             G04.run(root, manifest("lean"), execute: true)
  end

  test "G04-TEST-02 malformed or invalid law cannot be promoted by file presence", %{root: root} do
    approved(root)
    bad = manifest("lean")
    bad = put_in(bad, ["law", "theorem"], "nonexistent_law")
    assert {:error, _} = G04.run(root, bad)
    assert {:error, _} = Files.load(Path.join(@g04, "Law.lean"), ".tla")

    result = %{
      "reason" => nil,
      "stdout" => "",
      "stderr" => "",
      "exit_code" => 0
    }

    # Synthetic parser negative, NOT an actual Lean proof or engine acceptance.
    assert {:ok, normalized} = Lean.normalize(%{"property" => "grand_demo_reflexivity"}, result)
    assert normalized["status"] == "error"

    # A spoofed success string without an engine version cannot be proof.
    spoof = %{result | "stdout" => "'grand_demo_reflexivity' does not depend on any axioms\n"}
    assert {:ok, rejected} = Lean.normalize(%{"property" => "grand_demo_reflexivity"}, spoof)
    assert rejected["status"] == "error"

    # An explicitly qualified version with an axiom conflict must also fail.
    conflicting =
      spoof
      |> Map.put("version_output", "Lean (version 4.0.0)")
      |> Map.put("stdout", spoof["stdout"] <> "depends on axioms: [sorryAx]\n")

    assert {:ok, rejected} =
             Lean.normalize(%{"property" => "grand_demo_reflexivity"}, conflicting)

    assert rejected["status"] == "error"
  end

  test "G04-TEST-03 finite model imports as data and no jar is unsupported", %{root: root} do
    approved(root)
    assert {:ok, inspected} = G04.run(root, manifest("tlc"))
    assert inspected["status"] == "unrun"
    assert inspected["qualifications"]["bounds"] == %{"limit" => 2}
    assert inspected["qualifications"]["fairness"] == "none"
    assert {:ok, unsupported} = G04.run(root, manifest("tlc"), execute: true)
    assert unsupported["status"] == "unsupported"
    assert unsupported["runner"]["reason"] == "missing_tlc_jar"
  end

  test "G04-TEST-04 synthetic TLC output parser separates finite pass and trace", %{root: root} do
    approved(root)
    {:ok, prepared} = TLC.prepare(manifest("tlc"), [])

    good = %{
      "reason" => nil,
      "exit_code" => 0,
      "stdout" =>
        "TLC2 Version 2.18\n3 states generated, 3 distinct states found\nModel checking completed. No error has been found.\n",
      "stderr" => ""
    }

    assert {:ok, normalized} = TLC.normalize(prepared, good)
    assert normalized["status"] == "bounded_pass"

    bad = %{
      good
      | "exit_code" => 12,
        "stdout" =>
          "TLC2 Version 2.18\nError: Invariant Safe is violated.\nState 1: initial\nState 2: next\n3 states generated, 3 distinct states found\n"
    }

    assert {:ok, failed} = TLC.normalize(prepared, bad)
    assert failed["status"] == "counterexample"
    assert failed["counterexample"] =~ "State 2:"
    assert {:ok, rejected_zero} = TLC.normalize(prepared, %{bad | "exit_code" => 0})
    assert rejected_zero["status"] == "error"
    contradictory = %{good | "stdout" => good["stdout"] <> bad["stdout"]}
    assert {:ok, rejected_contradiction} = TLC.normalize(prepared, contradictory)
    assert rejected_contradiction["status"] == "error"

    forged = %{good | "exit_code" => 19}
    assert {:ok, rejected} = TLC.normalize(prepared, forged)
    assert rejected["status"] == "error"

    assert {:ok, rejected2} =
             TLC.normalize(prepared, %{
               bad
               | "stdout" => "TLC2 Version 2.18\nError: Invariant Safe is violated"
             })

    assert rejected2["status"] == "error"
  end

  test "G04-TEST-05 source mutation and current assumption changes invalidate applicability", %{
    root: root
  } do
    {opts, _} = approved(root)
    original = manifest("tlc")
    changed_path = Path.join(root, "Model.tla")
    File.cp!(original["model"]["file"], changed_path)
    current = put_in(original, ["model", "file"], changed_path)

    assert {:ok, result} = G04.run(root, current)
    assert {:ok, "current"} = G04.applicability(result, root, current)

    File.write!(
      changed_path,
      String.replace(File.read!(changed_path), "count <= Limit", "count < Limit")
    )

    assert {:ok, "stale"} = G04.applicability(result, root, current)
    File.cp!(original["model"]["file"], changed_path)
    assert {:ok, "current"} = G04.applicability(result, root, current)

    assert {:ok, _} = G03.revise_assumption(root, "g03-external-dedup", "attest", opts)
    assert {:ok, "stale"} = G04.applicability(result, root, current)
  end

  test "G04 exact historical binding, scope and assumption mismatches are rejected", %{
    root: root
  } do
    approved(root)
    original = manifest("tlc")

    assert {:error, :g04_requirement_revision_mismatch} =
             G04.run(root, put_in(original, ["requirement", "revision"], 2))

    assert {:error, :g04_assumption_revision_mismatch} =
             G04.run(root, put_in(original, ["assumptions", Access.at(0), "revision"], 2))

    assert {:error, :g04_source_scope_mismatch} =
             G04.run(root, put_in(original, ["source_refs", Access.at(0), "object_id"], "forged"))

    assert {:error, :g04_source_scope_mismatch} =
             G04.run(root, put_in(original, ["scope", "project_id"], "other"))
  end

  test "G04-TEST-06 synthetic runner missing engine, timeout, output cap and shell injection", %{
    root: root
  } do
    fake_dir = Path.join(root, "fake-bin")
    File.mkdir_p!(fake_dir)
    fake_lean = Path.join(fake_dir, "lean")
    File.write!(fake_lean, "#!/bin/sh\nsleep 2\n")
    File.chmod!(fake_lean, 0o755)
    previous = System.get_env("PATH") || ""

    try do
      System.put_env("PATH", fake_dir <> ":" <> previous)
      plan = %{"engine" => "lean", "args" => ["--version"], "files" => %{}}
      assert {:ok, raw} = Runner.execute(plan, execute: true, timeout_ms: 60)
      assert raw["reason"] == "timeout"

      assert {:error, :unsafe_runner_plan} =
               Runner.execute(%{plan | "args" => ["--version", "; touch /tmp/unsafe-g04"]},
                 execute: true
               )

      assert {:error, :unsafe_runner_plan} =
               Runner.execute(%{plan | "engine" => "sh", "args" => ["-c", "echo bad"]},
                 execute: true
               )

      assert {:ok, skipped} = Runner.execute(plan, [])
      assert skipped["reason"] == "unrun"

      File.write!(fake_lean, "#!/bin/sh\nprintf '%500s' x\n")
      assert {:ok, limited} = Runner.execute(plan, execute: true, output_limit_bytes: 256)
      assert limited["reason"] == "output_limit"
    after
      System.put_env("PATH", previous)
    end
  end

  test "unsafe symlink, malformed model scope and missing executable are rejected", %{
    root: root
  } do
    {_opts, _obligation} = approved(root)
    source = Path.join(@g04, "Model.tla")
    link = Path.join(root, "linked.tla")
    File.ln_s!(source, link)
    assert {:error, _} = Files.load(link, ".tla")

    invalid = manifest("tlc")
    invalid = put_in(invalid, ["model", "fairness"], "declared_in_spec")
    assert {:error, :invalid_tlc_scope_or_config} = G04.run(root, invalid)

    invalid = put_in(manifest("tlc"), ["model", "bounds", "limit"], 99)
    assert {:error, :invalid_tlc_scope_or_config} = G04.run(root, invalid)

    previous = System.get_env("PATH")

    try do
      System.put_env("PATH", "")
      plan = %{"engine" => "lean", "args" => ["--version"], "files" => %{}}
      assert {:ok, %{"reason" => "missing_engine"}} = Runner.execute(plan, execute: true)
    after
      if previous, do: System.put_env("PATH", previous), else: System.delete_env("PATH")
    end
  end

  test "cancel token is explicit; no implicit command executes", %{root: root} do
    path = Path.join(root, "lean")
    File.write!(path, "#!/bin/sh\nsleep 2\n")
    File.chmod!(path, 0o755)
    old = System.get_env("PATH") || ""

    try do
      System.put_env("PATH", root <> ":" <> old)
      token = make_ref()

      task =
        Task.async(fn ->
          Runner.execute(%{"engine" => "lean", "args" => ["--version"], "files" => %{}},
            execute: true,
            cancel_ref: token,
            timeout_ms: 1_000
          )
        end)

      Process.sleep(80)
      send(task.pid, {:g04_cancel, token})
      assert {:ok, %{"reason" => "cancelled"}} = Task.await(task, 2_000)
    after
      System.put_env("PATH", old)
    end
  end

  test "runner terminates descendants and separates output in a private workspace", %{root: root} do
    bin = Path.join(root, "bin")
    File.mkdir_p!(bin)
    marker = Path.join(root, "escaped")
    fake = Path.join(bin, "lean")
    File.write!(fake, "#!/bin/sh\n(sleep 0.4; touch \"#{marker}\") &\nsleep 2\n")
    File.chmod!(fake, 0o755)
    old = System.get_env("PATH") || ""
    plan = %{"engine" => "lean", "args" => ["--version"], "files" => %{}}

    try do
      System.put_env("PATH", bin <> ":" <> old)
      assert {:ok, %{"reason" => "timeout"}} = Runner.execute(plan, execute: true, timeout_ms: 80)
      Process.sleep(500)
      refute File.exists?(marker)
      File.write!(fake, "#!/bin/sh\nprintf 'out'; printf 'err' >&2; pwd; stat -c %a .\n")
      assert {:ok, raw} = Runner.execute(plan, execute: true)
      assert raw["stderr"] == "err"
      assert raw["stdout"] =~ "700"
      [workspace | _] = raw["stdout"] |> String.replace_prefix("out", "") |> String.split("\n")
      refute File.exists?(workspace)
    after
      System.put_env("PATH", old)
    end
  end

  test "real check qualification uses installed engines only; no test fixture counts as proof", %{
    root: root
  } do
    approved(root)
    law = manifest("lean")

    if System.find_executable("lean") && System.get_env("GRAND_RUN_LEAN") == "1" do
      assert {:ok, good} = G04.run(root, law, execute: true, allow_law_code: true)
      assert good["status"] == "proved"
      bad = put_in(law, ["law", "file"], Path.join(@g04, "InvalidLaw.lean"))
      assert {:ok, invalid} = G04.run(root, bad, execute: true, allow_law_code: true)
      assert invalid["status"] != "proved"
    else
      assert {:ok, unrun} = G04.run(root, law)
      assert unrun["status"] == "unrun"
    end

    jar = System.get_env("GRAND_TLC_JAR")

    if is_binary(jar) and File.regular?(jar) do
      assert {:ok, good} = G04.run(root, manifest("tlc"), execute: true, tlc_jar: jar)
      assert good["status"] == "bounded_pass"
      assert {:ok, bad} = G04.run(root, manifest("tlc-bad"), execute: true, tlc_jar: jar)
      assert bad["status"] == "counterexample"
      assert bad["counterexample"] =~ "State 2:"
    else
      assert {:ok, unsupported} = G04.run(root, manifest("tlc"), execute: true)
      assert unsupported["status"] == "unsupported"
    end
  end
end
