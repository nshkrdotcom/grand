defmodule Grand.BeamCompass.G03MotifTest do
  use ExUnit.Case, async: true

  alias Grand.BeamCompass
  alias Grand.BeamCompass.Motif
  alias Grand.BeamCompass.V2
  alias Grand.Core.JSON

  @fixtures Path.expand("../../../fixtures", __DIR__)

  test "G03-TEST-06 synthetic retry/effect motif yields deterministic contextual refs and omissions" do
    path = Path.join(@fixtures, "g03_synthetic_retry_v2.json")
    assert {:ok, env} = BeamCompass.import_file(path, project_id: "fixture:synthetic-retry")
    assert {:ok, candidate} = Motif.retry_external_effect(env)
    assert {:ok, ^candidate} = Motif.retry_external_effect(env)
    assert candidate["question"] =~ "Could retries"
    assert candidate["counterhypothesis"] =~ "idempotent"
    assert candidate["uncertainty"] =~ "No executed retry"
    assert candidate["context"]["source_mode"] == "source_only"
    assert candidate["context"]["query_receipt"]["omitted_count"] > 0
    assert is_list(candidate["context"]["query_receipt"]["unresolved"])
    assert Enum.any?(candidate["source_refs"], &(&1["object_kind"] == "relation"))
    assert Enum.any?(candidate["source_refs"], &(&1["object_kind"] == "evidence"))

    assert Enum.all?(candidate["source_refs"], fn ref ->
             match?({:ok, _}, BeamCompass.resolve(env, ref))
           end)
  end

  test "actual pinned P02B without retry-labelled typed effect relation yields NO candidate" do
    path = Path.join([@fixtures, "upstream", "beamcompass-p02b", "a.json"])
    assert {:ok, env} = BeamCompass.import_file(path, project_id: "fixture:ledger")

    assert {:error, :unsupported_retry_effect_motif_no_source_link} =
             Motif.retry_external_effect(env)
  end

  test "motif receipt preserves its typed link and accounts for every source object" do
    path = Path.join(@fixtures, "g03_synthetic_retry_v2.json")
    assert {:ok, env} = BeamCompass.import_file(path, project_id: "fixture:synthetic-retry")
    assert {:ok, candidate} = Motif.retry_external_effect(env)
    receipt = candidate["context"]["query_receipt"]
    relation = Enum.find(candidate["source_refs"], &(&1["object_kind"] == "relation"))
    assert Enum.any?(receipt["preserved"], &(&1["object_id"] == relation["object_id"]))
    assert receipt["omitted_count"] == length(receipt["omitted"])
    assert receipt["unresolved_count"] == length(receipt["unresolved"])
    upstream = env["upstream"]

    assert Enum.sum(Map.values(receipt["selected_counts"])) + length(receipt["omitted"]) ==
             length(upstream["entities"]) + length(upstream["relations"]) +
               length(upstream["evidence"])

    unresolved = Enum.filter(upstream["relations"], &(&1["resolution"] != "resolved"))

    assert Enum.sort(Enum.map(receipt["unresolved"], & &1["relation_id"])) ==
             Enum.sort(Enum.map(unresolved, & &1["id"]))
  end

  test "retry label without a resolved typed function to effect link is insufficient" do
    path = Path.join(@fixtures, "g03_synthetic_retry_v2.json")
    assert {:ok, env} = BeamCompass.import_file(path, project_id: "fixture:synthetic-retry")
    assert {:ok, candidate} = Motif.retry_external_effect(env)
    ref = Enum.find(candidate["source_refs"], &(&1["object_kind"] == "relation"))

    upstream =
      update_in(env["upstream"]["relations"], fn relations ->
        Enum.map(relations, fn r ->
          if r["id"] == ref["object_id"],
            do: %{
              r
              | "target_id" => nil,
                "resolution" => "unresolved",
                "epistemic_status" => "unresolved"
            },
            else: r
        end)
      end)["upstream"]

    {:ok, payload} = JSON.encode(Map.delete(upstream, "snapshot_id"))
    hash = :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
    upstream = Map.put(upstream, "snapshot_id", hash)
    {:ok, bytes} = JSON.encode(upstream)
    assert {:ok, mutated} = V2.import_data(upstream, bytes, project_id: "fixture:synthetic-retry")

    assert {:error, :unsupported_retry_effect_motif_no_source_link} =
             Motif.retry_external_effect(mutated)
  end
end
