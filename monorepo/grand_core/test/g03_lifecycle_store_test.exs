defmodule Grand.Core.G03LifecycleStoreTest do
  use ExUnit.Case, async: true

  alias Grand.Core
  alias Grand.Core.G03
  alias Grand.Core.JSON
  alias Grand.Core.LifecycleStore, as: Store

  @fixtures Path.expand("../../../fixtures", __DIR__)
  @at "2026-11-06T20:00:00Z"
  defp resolver, do: fn _ -> {:ok, %{"source_only" => true}} end

  setup do
    root = Path.join(System.tmp_dir!(), "grand-g03-core-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp candidate do
    {:ok, input} = JSON.decode(File.read!(Path.join(@fixtures, "g03_candidate_input.json")))

    Map.merge(input, %{
      "schema_version" => 2,
      "revision" => 1,
      "status" => "proposed",
      "context" => %{"motif" => nil, "query_receipt" => nil, "source_mode" => "source_only"},
      "events" => [event("propose", "agent:spike", 1, "untrusted_proposer")]
    })
  end

  defp event(action, actor, revision, assurance) do
    %{
      "action" => action,
      "actor" => actor,
      "at" => @at,
      "revision" => revision,
      "identity_assurance" => assurance
    }
  end

  defp rejected(c) do
    c
    |> Map.put("status", "rejected")
    |> Map.put("revision", 2)
    |> Map.update!(
      "events",
      &(&1 ++ [event("reject", "human:reviewer", 2, "self_attested_not_authenticated")])
    )
  end

  test "G03-TEST-04 interrupted pre-HEAD transaction preserves previous history", %{root: root} do
    first = candidate()
    assert {:ok, ^first} = Core.validate("candidate_v2", first)

    assert {:ok, %{"sequence" => 1}} =
             Store.append(root, "candidate", first, resolve_source: resolver())

    assert {:ok, previous_head} = Store.head(root)
    second = rejected(first)

    assert {:error, :injected_before_head} =
             Store.append(root, "candidate", second,
               resolve_source: resolver(),
               fault: :before_head
             )

    assert {:ok, ^previous_head} = Store.head(root)
    assert {:ok, [^first]} = Store.history(root, "candidate", first["id"])

    assert {:ok, %{"sequence" => 2}} =
             Store.append(root, "candidate", second,
               resolve_source: resolver(),
               expected_head: previous_head
             )

    assert {:ok, [^first, ^second]} = Store.history(root, "candidate", first["id"])
  end

  test "staged failure can retry the exact same immutable transaction", %{root: root} do
    record = candidate()

    assert {:error, :injected_before_commit} =
             Store.append(root, "candidate", record,
               resolve_source: resolver(),
               fault: :before_commit
             )

    assert {:ok, nil} = Store.head(root)
    assert {:ok, _} = Store.append(root, "candidate", record, resolve_source: resolver())
    assert {:ok, [^record]} = Store.history(root, "candidate", record["id"])
  end

  test "conflict, stale HEAD, and unauthorized same-revision changes are rejected", %{root: root} do
    initial = candidate()
    assert {:ok, _} = Store.append(root, "candidate", initial, resolve_source: resolver())

    assert {:error, :invalid_lifecycle_transition} =
             Store.append(root, "candidate", initial, resolve_source: resolver())

    assert {:error, :stale_lifecycle_head} =
             Store.append(root, "candidate", rejected(initial),
               resolve_source: resolver(),
               expected_head: nil
             )

    assert {:error, :invalid_lifecycle_transition} =
             Store.append(
               root,
               "candidate",
               %{rejected(initial) | "question" => "silently altered"},
               resolve_source: resolver()
             )
  end

  test "damaged immutable commit/HEAD rejects all reads, never silently repairs", %{root: root} do
    initial = candidate()

    assert {:ok, %{"head" => hash}} =
             Store.append(root, "candidate", initial, resolve_source: resolver())

    commit = Path.join([root, "g03_lifecycle_v2", "commits", hash <> ".json"])
    assert :ok = File.write(commit, "corruption", [:append])
    assert {:error, _} = Store.read(root)

    assert {:error, _} =
             Store.append(root, "candidate", rejected(initial), resolve_source: resolver())
  end

  test "corrupt HEAD and dangling exact source callback reject instead of changing state", %{
    root: root
  } do
    initial = candidate()
    assert {:error, :exact_source_resolver_required} = Store.append(root, "candidate", initial)

    assert {:error, {:unresolved_exact_source, :missing_fact}} =
             Store.append(root, "candidate", initial,
               resolve_source: fn _ -> {:error, :missing_fact} end
             )

    assert {:ok, nil} = Store.head(root)
    head_file = Path.join([root, "g03_lifecycle_v2", "HEAD.json"])
    assert :ok = File.write(head_file, "{\"digest\":\"forged\"}")
    assert {:error, _} = Store.read(root)
  end

  test "v2 strict scope and explicit status, no validation of plausible-looking forged refs" do
    record = candidate()

    assert {:error, _} =
             G03.validate(
               "candidate",
               put_in(record, ["source_refs", Access.at(0), "snapshot_id"], "different")
             )

    assert {:error, _} = G03.validate("candidate", %{record | "status" => "approved"})
    assert {:error, _} = G03.validate("candidate", %{record | "counterhypothesis" => ""})
    assert {:error, _} = G03.validate("candidate", %{record | "gaps" => []})
    assert {:error, _} = G03.validate("candidate", Map.put(record, "verified", true))
  end

  test "writer contention and conflicting orphan refuse publication and recover explicitly", %{
    root: root
  } do
    record = candidate()
    lock = Path.join([root, "g03_lifecycle_v2", "writer.lock"])
    File.mkdir_p!(lock)

    assert {:error, :lifecycle_writer_busy} =
             Store.append(root, "candidate", record, resolve_source: resolver())

    assert {:ok, nil} = Store.head(root)
    File.rmdir!(lock)

    assert {:error, :injected_before_head} =
             Store.append(root, "candidate", record,
               resolve_source: resolver(),
               fault: :before_head
             )

    [orphan] = Path.wildcard(Path.join([root, "g03_lifecycle_v2", "commits", "*.json"]))
    original = File.read!(orphan)
    File.write!(orphan, "tampered orphan")

    assert {:error, :lifecycle_commit_conflict} =
             Store.append(root, "candidate", record, resolve_source: resolver())

    assert {:ok, nil} = Store.head(root)
    assert File.read!(orphan) == "tampered orphan"
    # Explicit operator restoration of the orphan, not silent store repair.
    File.write!(orphan, original)
    assert {:ok, _} = Store.append(root, "candidate", record, resolve_source: resolver())
    assert {:ok, [^record]} = Store.history(root, "candidate", record["id"])
  end

  test "malformed audit events and implicit initial approval never enter journal", %{root: root} do
    record = candidate()

    for events <- [nil, ["forged"], [%{}], [nil]] do
      assert {:error, _} =
               Store.append(root, "candidate", %{record | "events" => events},
                 resolve_source: resolver()
               )
    end

    assert {:ok, nil} = Store.head(root)
  end
end
