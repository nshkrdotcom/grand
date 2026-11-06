defmodule Grand.Core.V2ReferenceTest do
  use ExUnit.Case, async: true
  alias Grand.Core

  @ref %{
    "schema_version" => 2,
    "provider" => "beamcompass",
    "upstream_schema_version" => 2,
    "project_id" => "fixture:ledger",
    "snapshot_id" => String.duplicate("a", 64),
    "object_kind" => "relation",
    "object_id" => "relation:read-only",
    "evidence_ids" => ["ev:1", "ev:2"],
    "epistemic_status" => "unresolved",
    "resolution" => "unresolved"
  }

  test "versioned reference permits all three P02B object collections" do
    ref = @ref
    assert {:ok, ^ref} = Core.validate("behavior_ref_v2", ref)
    entity = @ref |> Map.put("object_kind", "entity") |> Map.delete("resolution")
    assert {:ok, ^entity} = Core.validate("behavior_ref_v2", entity)
    evidence =
      @ref
      |> Map.put("object_kind", "evidence")
      |> Map.delete("epistemic_status")
      |> Map.delete("resolution")
      |> Map.put("evidence_ids", ["ev:1"])

    assert {:ok, ^evidence} = Core.validate("behavior_ref_v2", evidence)
  end

  test "bad v2 hashes, evidence order, mode promotion and v1 mixing fail" do
    for bad <- [
          Map.put(@ref, "snapshot_id", "wrong"),
          Map.put(@ref, "evidence_ids", ["ev:2", "ev:1"]),
          Map.put(@ref, "epistemic_status", "observed"),
          Map.put(@ref, "upstream_schema_version", 1),
          Map.put(@ref, "object_kind", "fact"),
          Map.put(@ref, "unknown", true)
        ] do
      assert {:error, {:invalid_record, "behavior_ref_v2", _}} = Core.validate("behavior_ref_v2", bad)
    end

    assert {:error, {:invalid_record, "behavior_ref", _}} = Core.validate("behavior_ref", @ref)
  end
end
