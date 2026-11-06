defmodule Grand.BeamCompass.ImportTest do
  use ExUnit.Case, async: true
  alias Grand.BeamCompass
  alias Grand.Core.JSON

  @fixtures Path.expand("../../../fixtures", __DIR__)
  @project "synthetic-ledger"

  setup do
    root = Path.join(System.tmp_dir!(), "grand-import-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "v1 fact stays source-grounded and exactly snapshot-scoped", %{root: root} do
    path = Path.join(@fixtures, "beamcompass_v1.json")
    original = File.read!(path)
    assert {:ok, snapshot} = BeamCompass.import_file(path, project_id: @project)

    assert snapshot["source_sha256"] ==
             Base.encode16(:crypto.hash(:sha256, original), case: :lower)

    assert [%{"confidence" => "provisional"}] = snapshot["capsule_assessments"]
    assert {:ok, ref} = BeamCompass.reference(snapshot, "synthetic-fact-void-intent-001")
    assert ref["epistemic_status"] == "source"
    assert ref["evidence_ids"] == [ref["object_id"]]
    assert {:ok, fact} = BeamCompass.resolve(snapshot, ref)

    assert fact["anchor"] == %{
             "path" => "lib/synthetic_hold/ledger.ex",
             "line" => 17,
             "column" => 3
           }

    assert {:ok, _} = BeamCompass.store(snapshot, root)
    assert {:ok, loaded} = BeamCompass.load(root, @project, snapshot["snapshot_id"])
    assert {:ok, ^fact} = BeamCompass.resolve(loaded, ref)
    assert original == File.read!(path)

    wrong = put_in(ref["snapshot_id"], "another-snapshot")
    assert {:error, {:reference_scope_mismatch, _}} = BeamCompass.resolve(loaded, wrong)
    wrong_kind = put_in(ref["object_kind"], "behavior")
    assert {:error, {:reference_scope_mismatch, _}} = BeamCompass.resolve(loaded, wrong_kind)
    promoted = put_in(ref["epistemic_status"], "observed")
    assert {:error, {:reference_evidence_mismatch, _}} = BeamCompass.resolve(loaded, promoted)
  end

  test "invalid version, duplicate facts, missing anchor, and traversal are rejected" do
    cases = [
      {"invalid_version.json", {:unsupported_schema_version, 99}},
      {"duplicate_fact.json", {:invalid_snapshot, :duplicate_fact_id}},
      {"missing_anchor.json", {:invalid_snapshot, :invalid_fact_or_anchor}},
      {"path_traversal.json", {:invalid_snapshot, :invalid_fact_or_anchor}}
    ]

    for {filename, reason} <- cases do
      assert {:error, ^reason} =
               BeamCompass.import_file(Path.join(@fixtures, filename), project_id: @project)
    end
  end

  test "import does not execute an apparent target project's mix.exs", %{root: root} do
    marker = Path.join(root, "would_run")
    target = Path.join(root, "target")
    File.mkdir_p!(target)
    File.write!(Path.join(target, "mix.exs"), "File.write!(#{inspect(marker)}, \"executed\")\n")
    path = Path.join(root, "input.json")
    input = File.read!(Path.join(@fixtures, "beamcompass_v1.json"))
    File.write!(path, input)
    assert {:ok, _snapshot} = BeamCompass.import_file(path, project_id: @project)
    refute File.exists?(marker)
  end

  test "unknown v1 fact and changed persisted JSON fail closed", %{root: root} do
    assert {:ok, snapshot} =
             BeamCompass.import_file(Path.join(@fixtures, "beamcompass_v1.json"),
               project_id: @project
             )

    assert {:error, {:unresolved_reference, "missing"}} =
             BeamCompass.reference(snapshot, "missing")

    assert {:ok, path} = BeamCompass.store(snapshot, root)
    assert {:ok, json} = JSON.decode(File.read!(path))
    mutated = put_in(json["upstream"]["facts"], [])
    assert {:ok, content} = JSON.encode(mutated)
    File.write!(path, content)

    assert {:error, {:invalid_snapshot, :stored_envelope_invalid_or_modified}} =
             BeamCompass.load(root, @project, snapshot["snapshot_id"])
  end
end
