defmodule Grand.BeamCompass.G03MotifTest do
  use ExUnit.Case, async: true

  alias Grand.BeamCompass
  alias Grand.BeamCompass.Motif

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
end
