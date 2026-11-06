defmodule Grand.BeamCompass.V2ImportTest do
  use ExUnit.Case, async: true

  alias Grand.BeamCompass
  alias Grand.BeamCompass.V2
  alias Grand.Core.JSON

  @pinned Path.expand("../../../fixtures/upstream/beamcompass-p02b", __DIR__)
  @legacy Path.expand("../../../fixtures/beamcompass_v1.json", __DIR__)
  @project "fixture:ledger"

  setup do
    root = Path.join(System.tmp_dir!(), "grand-g02-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp upstream(filename \\ "a.json") do
    {:ok, json} = JSON.decode(File.read!(Path.join(@pinned, filename)))
    json
  end

  defp rehash(snapshot) do
    {:ok, payload} = snapshot |> Map.delete("snapshot_id") |> JSON.encode()
    Map.put(snapshot, "snapshot_id", sha(payload))
  end

  defp sha(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp with_mutated_file(snapshot, root, fun) do
    {:ok, payload} = JSON.encode(rehash(snapshot))
    path = Path.join(root, "mutated-input.json")
    File.write!(path, payload)
    fun.(path)
  end

  test "G02-TEST-01 legacy v1 remains v1 and immutable", %{root: root} do
    {:ok, old} = BeamCompass.import_file(@legacy, project_id: "synthetic-ledger")
    assert old["schema_version"] == 1
    assert old["format"] == "grand.beamcompass.v1.import"
    assert {:ok, ref} = BeamCompass.reference(old, "synthetic-fact-void-intent-001")
    assert ref["object_kind"] == "fact"
    assert {:ok, _} = BeamCompass.resolve(old, ref)
    assert {:ok, _} = BeamCompass.store(old, root)
    assert {:ok, ^old} = BeamCompass.load(root, old["project_id"], old["snapshot_id"])

    assert {:error, :v2_snapshot_required} =
             BeamCompass.reference(old, "entity", ref["object_id"])

    assert {:error, :v2_object_kind_required} =
             BeamCompass.reference(%{"schema_version" => 2}, ref["object_id"])
  end

  test "G02-TEST-02 actual P02B v2 type, digest, exact reference and provenance", %{root: root} do
    for filename <- ["a.json", "mutated.json"] do
      raw = File.read!(Path.join(@pinned, filename))
      {:ok, env} = BeamCompass.import_file(Path.join(@pinned, filename), project_id: @project)
      assert env["schema_version"] == 2
      assert env["snapshot_id"] == upstream(filename)["snapshot_id"]
      assert env["source_sha256"] == sha(raw)
      assert Enum.all?(env["upstream"]["manifest"]["providers"], &(&1["mode"] == "source"))
      assert Enum.all?(env["upstream"]["evidence"], &(&1["mode"] == "source"))
      assert {:ok, _} = BeamCompass.store(env, root)
      assert {:ok, loaded} = BeamCompass.load(root, @project, env["snapshot_id"], 2)
      assert loaded == env

      for {kind, list} <- [
            {"entity", loaded["upstream"]["entities"]},
            {"relation", loaded["upstream"]["relations"]},
            {"evidence", loaded["upstream"]["evidence"]}
          ],
          object <- list do
        assert {:ok, ref} = BeamCompass.reference(loaded, kind, object["id"])
        assert {:ok, ^object} = BeamCompass.resolve(loaded, ref)
        assert ref["schema_version"] == 2

        assert ref["evidence_ids"] ==
                 if(kind == "evidence", do: [object["id"]], else: object["evidence_ids"])
      end
    end

    for filename <- ["exact-0.json", "exact-1.json"] do
      {:ok, ref} = JSON.decode(File.read!(Path.join(@pinned, filename)))
      {:ok, env} = BeamCompass.import_file(Path.join(@pinned, "a.json"), project_id: @project)
      assert ref["snapshot_schema_version"] == 2
      assert {:ok, local} = BeamCompass.reference(env, "entity", ref["object_id"])
      assert local["evidence_ids"] == ref["evidence_ids"]
      assert local["snapshot_id"] == ref["snapshot_id"]
      # Upstream P02B's own reference contract uses snapshot_schema_version;
      # Grand's versioned reference deliberately uses upstream_schema_version.
      translated =
        ref
        |> Map.delete("snapshot_schema_version")
        |> Map.put("schema_version", 2)
        |> Map.put("upstream_schema_version", ref["snapshot_schema_version"])

      assert {:ok, _} = BeamCompass.resolve(env, translated)
    end
  end

  test "G02-TEST-03 unresolved performer and dynamic link remain unknown", %{root: root} do
    {:ok, env} = BeamCompass.import_file(Path.join(@pinned, "a.json"), project_id: @project)

    relation =
      Enum.find(env["upstream"]["relations"], fn r ->
        r["resolution"] == "unresolved" and r["target_id"] == nil
      end)

    assert relation["epistemic_status"] == "unresolved"
    assert {:ok, ref} = BeamCompass.reference(env, "relation", relation["id"])
    assert {:ok, ^relation} = BeamCompass.resolve(env, ref)
    assert ref["resolution"] == "unresolved"

    assert {:ok, query} =
             BeamCompass.query(env,
               focus: relation["source_id"],
               budget: 3,
               preserve: [%{"object_kind" => "relation", "object_id" => relation["id"]}]
             )

    assert Enum.any?(query["relations"], &(&1["id"] == relation["id"]))
    assert Enum.any?(query["receipt"]["unresolved"], &(&1["relation_id"] == relation["id"]))
    assert query["epistemic_scope"] == "source_only_no_runtime_or_causal_claim"
    assert {:ok, _} = BeamCompass.store(env, root)
  end

  test "G02-TEST-04 preservation, budget error and complete omission receipts" do
    {:ok, env} = BeamCompass.import_file(Path.join(@pinned, "a.json"), project_id: @project)
    relation = Enum.find(env["upstream"]["relations"], &(&1["resolution"] == "resolved"))
    preserve = [%{"object_kind" => "relation", "object_id" => relation["id"]}]
    focus = relation["source_id"]

    assert {:error, {:preservation_budget_exceeded, 3, 1}} =
             BeamCompass.query(env, focus: focus, budget: 1, preserve: preserve)

    assert {:ok, query} = BeamCompass.query(env, focus: focus, budget: 3, preserve: preserve)
    assert length(query["relations"]) == 1
    assert length(query["entities"]) == 2
    assert query["receipt"]["omitted_count"] > 0
    assert query["receipt"]["unresolved_count"] > 0
    assert query["receipt"]["selected_graph_complete"] == false
    assert query["receipt"]["semantic_completeness"] == "not_claimed"
    assert Enum.any?(query["receipt"]["preserved"], &(&1["object_id"] == relation["id"]))

    assert length(query["receipt"]["omitted"]) ==
             length(env["upstream"]["entities"]) + length(env["upstream"]["relations"]) +
               length(env["upstream"]["evidence"]) -
               length(query["entities"]) - length(query["relations"]) - length(query["evidence"])

    assert {:error, {:unresolved_preserve_references, _}} =
             BeamCompass.query(env,
               focus: focus,
               preserve: [%{"object_kind" => "relation", "object_id" => "missing"}]
             )

    assert {:error, {:invalid_query_budget, 257, 256}} =
             BeamCompass.query(env, focus: focus, budget: 257)

    assert {:error, {:unsupported_local_query_lens, "proof"}} =
             BeamCompass.query(env, focus: focus, lens: "proof")
  end

  test "G02-TEST-05 version and project mismatch fail without data loss", %{root: root} do
    old = upstream() |> Map.put("schema_version", 99)

    with_mutated_file(old, root, fn path ->
      assert {:error, {:unsupported_schema_version, 99}} =
               BeamCompass.import_file(path, project_id: @project)
    end)

    assert {:error, {:invalid_v2_snapshot, :project_id_mismatch}} =
             BeamCompass.import_file(Path.join(@pinned, "a.json"), project_id: "other")

    assert {:error, :project_id_required} =
             BeamCompass.import_file(Path.join(@pinned, "a.json"), [])

    refute File.exists?(Path.join(root, "snapshots_v2"))
  end

  test "hostile v2 rehashed shape, graph, mode, type, order and path are refused", %{root: root} do
    a = upstream()
    first_evidence = hd(a["evidence"])
    first_entity = hd(a["entities"])
    effect_intent = Enum.find(a["entities"], &(&1["kind"] == "effect_intent"))

    effect_rel =
      Enum.find(
        a["relations"],
        &(&1["kind"] == "performs_effect" and &1["resolution"] == "resolved")
      )

    attacks = [
      {"duplicate entity ID", update_in(a["entities"], &List.insert_at(&1, 0, hd(&1)))},
      {"dangling entity evidence",
       put_in(a["entities"], [
         Map.put(first_entity, "evidence_ids", ["missing"]) | tl(a["entities"])
       ])},
      {"missing provider",
       put_in(a["evidence"], [
         Map.put(first_evidence, "provider_id", "missing") | tl(a["evidence"])
       ])},
      {"evidence cycle",
       put_in(a["evidence"], [
         Map.put(first_evidence, "input_evidence_ids", [first_evidence["id"]]) | tl(a["evidence"])
       ])},
      {"compiled provider",
       put_in(a["manifest"]["providers"], [
         Map.put(hd(a["manifest"]["providers"]), "mode", "compiled")
       ])},
      {"observed evidence",
       put_in(a["evidence"], [Map.put(first_evidence, "mode", "observed") | tl(a["evidence"])])},
      {"observed entity",
       put_in(a["entities"], [
         Map.put(first_entity, "epistemic_status", "observed") | tl(a["entities"])
       ])},
      {"traversal",
       put_in(a["evidence"], [
         put_in(first_evidence["anchor"]["path"], "../secrets") | tl(a["evidence"])
       ])},
      {"end before start",
       put_in(a["evidence"], [
         put_in(first_evidence["anchor"]["end_line"], 1) |> put_in(["anchor", "end_column"], 1)
         | tl(a["evidence"])
       ])},
      {"wrong typed effect",
       update_in(a["relations"], fn rels ->
         Enum.map(rels, fn r ->
           if r["id"] == effect_rel["id"],
             do: Map.put(r, "target_id", effect_intent["id"]),
             else: r
         end)
       end)},
      {"unsorted entities", put_in(a["entities"], Enum.reverse(a["entities"]))},
      {"dangling source",
       update_in(a["relations"], fn rels ->
         [Map.put(hd(rels), "source_id", "not-present") | tl(rels)]
       end)}
    ]

    for {label, forged} <- attacks do
      with_mutated_file(forged, root, fn path ->
        assert {:error, {:invalid_v2_snapshot, _}} =
                 BeamCompass.import_file(path, project_id: @project),
               label
      end)
    end

    assert {:error, {:invalid_v2_snapshot, :snapshot_digest_mismatch}} =
             V2.validate_snapshot(
               update_in(a["limitations"], &Enum.sort(["A changed limitation" | &1]))
             )
  end

  test "exact v2 refs reject wrong collection, evidence, state and snapshot", %{root: root} do
    {:ok, env} = BeamCompass.import_file(Path.join(@pinned, "a.json"), project_id: @project)
    relation = hd(env["upstream"]["relations"])
    {:ok, reference} = BeamCompass.reference(env, "relation", relation["id"])

    assert {:error, {:unresolved_reference, "evidence", _}} =
             BeamCompass.resolve(
               env,
               Map.put(reference, "object_kind", "evidence")
               |> Map.delete("resolution")
               |> Map.delete("epistemic_status")
             )

    assert {:error, {:reference_evidence_mismatch, _}} =
             BeamCompass.resolve(env, Map.put(reference, "evidence_ids", ["evidence:bogus"]))

    assert {:error, {:reference_evidence_mismatch, _}} =
             BeamCompass.resolve(env, Map.put(reference, "resolution", "possible"))

    assert {:error, {:reference_scope_mismatch, _}} =
             BeamCompass.resolve(
               env,
               Map.put(reference, "snapshot_id", String.duplicate("f", 64))
             )

    assert {:error, {:invalid_record, "behavior_ref_v2", _}} =
             BeamCompass.resolve(env, Map.put(reference, "object_kind", "fact"))

    assert {:error, {:unresolved_reference, "entity", "unknown"}} =
             BeamCompass.reference(env, "entity", "unknown")

    assert {:ok, stored} = BeamCompass.store(env, root)
    assert {:ok, _} = BeamCompass.store(env, root)
    assert File.exists?(stored)
    changed = Map.put(env, "source_sha256", String.duplicate("f", 64))
    assert {:error, :immutable_record_conflict} = BeamCompass.store(changed, root)
    File.write!(stored, "{}")

    assert {:error, {:invalid_v2_snapshot, _}} =
             BeamCompass.load(root, @project, env["snapshot_id"], 2)
  end

  test "hostile serialization and input size, no target code is evaluated", %{root: root} do
    input = Path.join(root, "bad.json")
    File.write!(input, "{\"schema_version\":2,\"schema_version\":2}")

    assert {:error, {:invalid_json, :duplicate_key}} =
             BeamCompass.import_file(input, project_id: @project)

    File.write!(input, String.duplicate(" ", 4_000_001))

    assert {:error, :invalid_project_or_oversized_input} =
             BeamCompass.import_file(input, project_id: @project)

    File.write!(input, String.duplicate("[", 100) <> "0" <> String.duplicate("]", 100))

    assert {:error, {:invalid_json, :depth_limit}} =
             BeamCompass.import_file(input, project_id: @project)

    marker = Path.join(root, "target_exec_marker")
    File.write!(Path.join(root, "mix.exs"), "File.write!(#{inspect(marker)}, \"executed\")\n")
    assert {:ok, _} = BeamCompass.import_file(Path.join(@pinned, "a.json"), project_id: @project)
    refute File.exists?(marker)
  end
end
