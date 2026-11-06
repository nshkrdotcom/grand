defmodule Grand.CLI.G02IntegrationTest do
  use ExUnit.Case, async: false
  alias Grand.Core.JSON

  @pinned Path.expand("../../../fixtures/upstream/beamcompass-p02b", __DIR__)
  @cli_root Path.expand("..", __DIR__)
  @project "fixture:ledger"

  setup do
    root = Path.join(System.tmp_dir!(), "grand-g02-cli-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp cli(args) do
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
        nil -> {:error, :no_stdout}
        last -> JSON.decode(last)
      end

    {status, parsed, output}
  end

  test "real CLI P02B import inspect entity/relation/evidence query and export", %{root: root} do
    store = Path.join(root, "store")
    original = Path.join(@pinned, "a.json")
    {:ok, upstream} = JSON.decode(File.read!(original))
    snapshot_id = upstream["snapshot_id"]
    entity = hd(upstream["entities"])
    relation = hd(upstream["relations"])
    evidence = hd(upstream["evidence"])
    out = Path.join(root, "roundtrip.json")
    query_file = Path.join(root, "query.json")

    {0, {:ok, imported}, _} =
      cli(["import", original, "--project", @project, "--schema", "2", "--store", store])

    assert imported["snapshot_id"] == snapshot_id
    assert imported["entity_count"] == length(upstream["entities"])
    assert imported["relation_count"] == length(upstream["relations"])
    assert imported["epistemic_scope"] == "source_only_no_runtime_claim"

    for {kind, object} <- [{"entity", entity}, {"relation", relation}, {"evidence", evidence}] do
      {0, {:ok, inspected}, _} =
        cli([
          "inspect",
          kind,
          @project,
          snapshot_id,
          object["id"],
          "--schema",
          "2",
          "--store",
          store
        ])

      assert inspected["upstream_object"] == object
      assert inspected["behavior_ref"]["object_kind"] == kind
    end

    {0, {:ok, inspected_snapshot}, _} =
      cli(["inspect", "snapshot", @project, snapshot_id, "--schema", "2", "--store", store])

    assert inspected_snapshot["upstream"] == upstream

    focus = relation["source_id"]

    {0, {:ok, q}, _} =
      cli([
        "query",
        @project,
        snapshot_id,
        "--focus",
        focus,
        "--budget",
        "3",
        "--preserve",
        "relation=" <> relation["id"],
        "--lens",
        "neighbors",
        "--store",
        store,
        "--out",
        query_file
      ])

    assert q["receipt"]["omitted_count"] > 0
    assert {:ok, full_query} = JSON.decode(File.read!(query_file))
    assert full_query["format"] == "grand.local_query.v1"
    assert full_query["receipt"]["unresolved_count"] > 0

    {0, {:ok, exported}, _} =
      cli([
        "export",
        "snapshot",
        @project,
        snapshot_id,
        "--schema",
        "2",
        "--store",
        store,
        "--out",
        out
      ])

    assert exported["epistemic_scope"] == "source_only_no_runtime_claim"
    assert {:ok, ^upstream} = JSON.decode(File.read!(out))

    {status, _, _} =
      cli([
        "export",
        "snapshot",
        @project,
        snapshot_id,
        "--schema",
        "2",
        "--store",
        store,
        "--out",
        out
      ])

    assert status != 0
  end

  test "CLI refuses wrong version, partial preserve, invalid budget and cross-project", %{
    root: root
  } do
    store = Path.join(root, "store")
    original = Path.join(@pinned, "a.json")
    {:ok, upstream} = JSON.decode(File.read!(original))
    snapshot_id = upstream["snapshot_id"]
    focus = hd(upstream["entities"])["id"]

    {status, _, text} =
      cli(["import", original, "--schema", "1", "--project", @project, "--store", store])

    assert status != 0
    assert text =~ "schema_version_mismatch"

    {status, _, text} =
      cli(["import", original, "--schema", "2", "--project", "foreign", "--store", store])

    assert status != 0
    assert text =~ "project_id_mismatch"
    refute File.exists?(Path.join(store, "snapshots_v2"))

    {0, {:ok, _}, _} = cli(["import", original, "--project", @project, "--store", store])

    for {flags, error_text} <- [
          {["--budget", "0"], "invalid_query_budget"},
          {["--budget", "257"], "invalid_query_budget"},
          {["--preserve", "relation=missing"], "unresolved_preserve_references"},
          {["--preserve", "fact=wrong"], "invalid_preserve_option"},
          {["--lens", "proof"], "unsupported_local_query_lens"}
        ] do
      {code, _, output} =
        cli(["query", @project, snapshot_id, "--focus", focus, "--store", store] ++ flags)

      assert code != 0
      assert output =~ error_text
    end
  end

  test "both actual exports roundtrip and required relation budget rejects", %{root: root} do
    for filename <- ["a.json", "mutated.json"] do
      original = Path.join(@pinned, filename)
      {:ok, upstream} = JSON.decode(File.read!(original))
      sid = upstream["snapshot_id"]
      relation = Enum.find(upstream["relations"], &(&1["resolution"] == "resolved"))
      store = Path.join(root, filename <> "-store")

      {0, {:ok, _}, _} =
        cli(["import", original, "--project", @project, "--schema", "2", "--store", store])

      args = [
        "query",
        @project,
        sid,
        "--focus",
        relation["source_id"],
        "--preserve",
        "relation=" <> relation["id"],
        "--store",
        store
      ]

      {status, _, output} = cli(args ++ ["--budget", "1"])
      assert status != 0
      assert output =~ "preservation_budget_exceeded"
      out = Path.join(root, filename <> "-query.json")
      {0, {:ok, _}, _} = cli(args ++ ["--budget", "3", "--out", out])
      {:ok, query} = JSON.decode(File.read!(out))
      assert Enum.any?(query["receipt"]["preserved"], &(&1["object_id"] == relation["id"]))
      assert query["receipt"]["omitted"] != []
      assert query["receipt"]["unresolved"] != []
      {status, _, _} = cli(args ++ ["--budget", "3", "--out", out])
      assert status != 0
      portable = Path.join(root, filename <> "-portable.json")

      {0, {:ok, _}, _} =
        cli([
          "export",
          "snapshot",
          @project,
          sid,
          "--schema",
          "2",
          "--store",
          store,
          "--out",
          portable
        ])

      {0, {:ok, imported}, _} =
        cli([
          "import",
          portable,
          "--project",
          @project,
          "--schema",
          "2",
          "--store",
          store <> "-roundtrip"
        ])

      assert imported["snapshot_id"] == sid

      {status, _, output} =
        cli([
          "import",
          original,
          "--project",
          @project,
          "--store",
          store,
          "--imagined-option",
          "yes"
        ])

      assert status != 0
      assert output =~ "invalid_cli_options"
    end
  end
end
