defmodule Grand.CLI.IntegrationTest do
  use ExUnit.Case, async: false
  alias Grand.Core.JSON

  @fixtures Path.expand("../../../fixtures", __DIR__)
  @cli_root Path.expand("..", __DIR__)
  @time "2026-11-06T21:00:00Z"
  @requirement "synthetic-REQ-void-confirmation"
  @snapshot "synthetic-hold-snapshot-001"
  @fact "synthetic-fact-void-intent-001"
  @project "synthetic-ledger"

  setup do
    root = Path.join(System.tmp_dir!(), "grand-cli-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp mix_command(args) do
    {output, status} =
      System.cmd("mix", ["grand" | args],
        cd: @cli_root,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    parsed =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> case do
        nil -> {:error, :no_output}
        line -> JSON.decode(line)
      end

    {status, parsed, output}
  end

  test "real Mix CLI import -> link -> approve -> inspect -> export", %{root: root} do
    source = Path.join(@fixtures, "beamcompass_v1.json")
    source_bytes = File.read!(source)
    store = Path.join(root, "records")
    output_path = Path.join(root, "export.json")

    {0, {:ok, imported}, _} =
      mix_command(["import", source, "--project", @project, "--store", store])

    assert imported["snapshot_id"] == @snapshot
    assert imported["epistemic_scope"] == "syntactic_source_only"

    {0, {:ok, linked}, _} =
      mix_command([
        "link", Path.join(@fixtures, "requirement_pending.json"),
        "--project", @project, "--snapshot", @snapshot, "--fact", @fact,
        "--actor", "human:fixture-submitter", "--at", @time, "--store", store
      ])

    assert linked["status"] == "pending_approval"
    assert linked["behavior_ref"]["epistemic_status"] == "source"

    {0, {:ok, approved}, _} =
      mix_command([
        "approve", @requirement, "--actor", "human:fixture-reviewer",
        "--ack-human", "--at", @time, "--store", store
      ])

    assert approved["status"] == "approved"
    assert approved["revision"] == 2
    assert approved["identity_assurance"] == "self_attested_not_authenticated"

    {0, {:ok, inspected}, _} =
      mix_command(["inspect", "requirement", @requirement, "--store", store])

    assert inspected["status"] == "approved"
    assert length(inspected["approval_events"]) == 2

    {0, {:ok, fact_record}, _} =
      mix_command(["inspect", "fact", @project, @snapshot, @fact, "--store", store])

    assert fact_record["upstream_fact"]["anchor"]["line"] == 17

    {0, {:ok, exported}, _} =
      mix_command([
        "export", @requirement, "--project", @project,
        "--store", store, "--out", output_path
      ])

    assert exported["verification_status"] == "unrun"
    assert {:ok, bundle} = JSON.decode(File.read!(output_path))
    assert bundle["verification_result"]["status"] == "unrun"
    assert bundle["assurance_record"]["coverage_summary"]["status"] == "unassessed"
    assert bundle["behavior_ref"]["snapshot_id"] == @snapshot
    assert bundle["requirement"]["status"] == "approved"
    assert source_bytes == File.read!(source)

    {1, _, _} =
      mix_command([
        "export", @requirement, "--project", @project,
        "--store", store, "--out", output_path
      ])
  end

  test "unknown version fails subprocess import and creates no persisted snapshot", %{root: root} do
    store = Path.join(root, "records")

    {status, _parsed, output} =
      mix_command([
        "import", Path.join(@fixtures, "invalid_version.json"),
        "--project", @project, "--store", store
      ])

    assert status != 0
    assert output =~ "unsupported_schema_version"
    refute File.exists?(Path.join(store, "snapshots"))
  end
end
