defmodule Grand.CLI.G03IntegrationTest do
  use ExUnit.Case, async: false

  alias Grand.Core.JSON

  @fixtures Path.expand("../../../fixtures", __DIR__)
  @cli_root Path.expand("..", __DIR__)
  @time "2026-11-06T20:00:00Z"
  @project "fixture:synthetic-retry"
  @human ["--actor", "human:local-reviewer", "--ack-human", "--at", @time]

  setup do
    root = Path.join(System.tmp_dir!(), "grand-g03-cli-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, store: Path.join(root, "store")}
  end

  defp cmd(args) do
    {out, status} = System.cmd("mix", ["grand" | args], cd: @cli_root,
      env: [{"MIX_ENV", "test"}], stderr_to_stdout: true)

    result =
      out
      |> String.split("\n", trim: true)
      |> List.last()
      |> case do
        nil -> {:error, :empty_output}
        last -> JSON.decode(last)
      end

    {status, result, out}
  end

  defp fixture(name), do: Path.join(@fixtures, "g03_#{name}_input.json")
  defp import_source(store) do
    source = Path.join(@fixtures, "g03_synthetic_retry_v2.json")
    {0, {:ok, imported}, _} = cmd(["import", source, "--project", @project,
      "--schema", "2", "--store", store])
    imported["snapshot_id"]
  end

  test "real mix grand G03 v2 lifecycle, historical references and conditional receipt", %{store: store, root: root} do
    _snapshot = import_source(store)
    {0, {:ok, assumption}, _} = cmd(["g03", "assumption", "register", fixture("assumption"),
      "--store", store] ++ @human)
    assert assumption["status"] == "open"

    {0, {:ok, draft}, _} = cmd(["g03", "requirement", "draft", fixture("requirement"),
      "--store", store] ++ @human)
    assert draft["status"] == "draft"

    {status, _, output} = cmd(["g03", "requirement", "approve", draft["id"],
      "--store", store, "--actor", "agent:assistant", "--ack-human"])
    assert status != 0
    assert output =~ "explicit_human_review_ack_required"

    {0, {:ok, pending}, _} = cmd(["g03", "requirement", "submit", draft["id"],
      "--store", store] ++ @human)
    assert pending["revision"] == 2
    {0, {:ok, approved}, _} = cmd(["g03", "requirement", "approve", draft["id"],
      "--store", store] ++ @human)
    assert approved["revision"] == 3
    assert approved["status"] == "approved"

    {0, {:ok, historical}, _} = cmd(["g03", "inspect", "requirement", draft["id"],
      "--revision", "1", "--store", store])
    assert historical == draft
    {0, {:ok, history}, _} = cmd(["g03", "history", "requirement", draft["id"],
      "--store", store])
    assert history == [draft, pending, approved]

    {0, {:ok, attested}, _} = cmd(["g03", "assumption", "attest", assumption["id"],
      "--store", store] ++ @human)
    assert attested["revision"] == 2
    assert attested["status"] == "attested"
    {status, _, _} = cmd(["g03", "assumption", "discharge", assumption["id"],
      "--store", store] ++ @human)
    assert status != 0

    {0, {:ok, obligation}, _} = cmd(["g03", "obligation", "create", fixture("obligation"),
      "--store", store] ++ @human)
    assert obligation["status"] == "unrun"

    receipt_path = Path.join(root, "conditional.json")
    {0, {:ok, exported}, _} = cmd(["g03", "receipt", obligation["id"],
      "--store", store, "--out", receipt_path])
    assert exported["verification_status"] == "unrun"
    {:ok, receipt} = JSON.decode(File.read!(receipt_path))
    assert receipt["verification_result"]["status"] == "unrun"
    assert receipt["coverage_summary"]["status"] == "unassessed"
    assert receipt["assumption_revisions"] |> hd() |> get_in(["current", "status"]) ==
             "attested"
    assert receipt["witness_challenge"]["feasibility"] == "not_checked"
    assert receipt["open_gaps"] != []
    {status, _, _} = cmd(["g03", "receipt", obligation["id"],
      "--store", store, "--out", receipt_path])
    assert status != 0
  end

  test "real mix grand source-backed motif proposal and human rejection are not auto-approval", %{store: store} do
    snapshot = import_source(store)
    {0, {:ok, question}, _} = cmd(["g03", "motif", "propose", @project, snapshot,
      "--store", store, "--actor", "agent:deterministic-motif", "--at", @time])
    assert question["status"] == "proposed"
    assert question["context"]["query_receipt"]["omitted_count"] > 0
    assert question["counterhypothesis"] != ""
    assert question["source_refs"] != []

    {status, _, _} = cmd(["g03", "requirement", "approve", question["id"],
      "--store", store] ++ @human)
    assert status != 0

    {status, _, _} = cmd(["g03", "candidate", "reject", question["id"],
      "--store", store, "--actor", "agent:reviewer", "--ack-human"])
    assert status != 0

    {0, {:ok, rejected}, _} = cmd(["g03", "candidate", "reject", question["id"],
      "--store", store] ++ @human)
    assert rejected["revision"] == 2
    assert rejected["status"] == "rejected"
    {0, {:ok, history}, _} = cmd(["g03", "history", "candidate", question["id"],
      "--store", store])
    assert history == [question, rejected]
  end
end
