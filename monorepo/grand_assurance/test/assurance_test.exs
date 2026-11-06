defmodule Grand.AssuranceTest do
  use ExUnit.Case, async: true
  alias Grand.Assurance
  alias Grand.Core

  @time "2026-11-06T21:00:00Z"

  defp reference do
    %{
      "schema_version" => 1,
      "provider" => "beamcompass",
      "project_id" => "synthetic-ledger",
      "snapshot_id" => "synthetic-hold-snapshot-001",
      "upstream_schema_version" => 1,
      "object_kind" => "fact",
      "object_id" => "synthetic-fact-void-intent-001",
      "evidence_ids" => ["synthetic-fact-void-intent-001"],
      "epistemic_status" => "source",
      "limitations" => ["syntactic only"]
    }
  end

  defp pending do
    %{
      "schema_version" => 1,
      "id" => "synthetic-REQ-void-confirmation",
      "revision" => 1,
      "statement" => "A void intent cannot by itself release held capacity.",
      "status" => "pending_approval",
      "owner" => "fixture-owner",
      "approval_events" => [],
      "behavior_refs" => [],
      "assumption_ids" => []
    }
  end

  test "manual link is separate from descriptive facts and approval makes a new revision" do
    ref = reference()
    assert {:ok, linked} =
             Assurance.link_requirement(pending(), ref, actor: "human:submitter", at: @time)

    assert linked["status"] == "pending_approval"
    assert linked["behavior_refs"] == [ref]
    assert linked["approval_events"] |> hd() |> Map.get("action") == "submit"

    assert {:ok, approved} =
             Assurance.approve(linked, actor: "human:reviewer", at: @time, ack_human: true)

    assert approved["revision"] == 2
    assert approved["status"] == "approved"
    assert length(approved["approval_events"]) == 2
    assert {:ok, ^approved} = Core.validate("requirement", approved)
    assert ref["epistemic_status"] == "source"

    assert {:ok, bundle} = Assurance.unrun_bundle(approved, ref, String.duplicate("a", 64))
    assert bundle["verification_result"]["status"] == "unrun"
    assert bundle["assurance_record"]["coverage_summary"]["status"] == "unassessed"
    assert bundle["obligation"]["kind"] == "other"
    refute Map.has_key?(bundle["verification_result"], "verified")
    assert {:ok, ^bundle} = Assurance.unrun_bundle(approved, ref, String.duplicate("a", 64))
  end

  test "agent and unauthorised approval paths are rejected" do
    ref = reference()

    assert {:error, :human_identity_label_required} =
             Assurance.link_requirement(pending(), ref, actor: "agent:chatgpt", at: @time)

    assert {:ok, linked} =
             Assurance.link_requirement(pending(), ref, actor: "human:writer", at: @time)

    assert {:error, :human_identity_label_required} =
             Assurance.approve(linked, actor: "ai:assistant", at: @time, ack_human: true)

    assert {:error, :approval_requires_pending_link_and_explicit_human_acknowledgement} =
             Assurance.approve(linked, actor: "human:reviewer", at: @time)

    assert {:error, :requirement_must_be_new_unlinked_pending_revision_one} =
             Assurance.link_requirement(linked, ref, actor: "human:writer", at: @time)
  end

  test "append-only requirement history is available through latest view" do
    root = Path.join(System.tmp_dir!(), "grand-assurance-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, linked} =
             Assurance.link_requirement(pending(), reference(), actor: "human:writer", at: @time)

    assert {:ok, _} = Assurance.save_requirement(root, linked)
    assert {:ok, revision2} =
             Assurance.approve(linked, actor: "human:reviewer", at: @time, ack_human: true)

    assert {:ok, _} = Assurance.save_requirement(root, revision2)
    assert {:ok, ^revision2} = Assurance.latest(root, linked["id"])
    assert {:error, :immutable_record_conflict} =
             Assurance.save_requirement(root, %{revision2 | "statement" => "silently changed"})
  end
end
