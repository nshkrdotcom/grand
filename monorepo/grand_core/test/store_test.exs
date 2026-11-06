defmodule Grand.Core.StoreTest do
  use ExUnit.Case, async: true
  alias Grand.Core.Store

  setup do
    root = Path.join(System.tmp_dir!(), "grand-core-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "idempotent append-only store refuses immutable overwrite", %{root: root} do
    assert {:ok, path} = Store.put(root, "snapshots", "id-1", %{"value" => 1})
    assert File.exists?(path)
    assert {:ok, ^path} = Store.put(root, "snapshots", "id-1", %{"value" => 1})
    assert {:error, :immutable_record_conflict} =
             Store.put(root, "snapshots", "id-1", %{"value" => 2})
    assert {:ok, %{"value" => 1}} = Store.get(root, "snapshots", "id-1")
  end
end
