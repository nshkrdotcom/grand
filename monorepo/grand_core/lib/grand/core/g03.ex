defmodule Grand.Core.G03 do
  @moduledoc """
  Strict, additive v2 normative-record contracts. These are NOT migrations of the
  legacy v1 requirement/obligation records. Validation is structural; cross-record
  and exact imported-source resolution occur at the transaction boundary.
  """

  alias Grand.Core

  @kinds ~w(candidate requirement assumption obligation)
  @statuses %{
    "candidate" => ~w(proposed rejected superseded),
    "requirement" => ~w(draft pending_approval approved rejected superseded),
    "assumption" => ~w(open attested tested discharged invalidated superseded),
    "obligation" => ~w(unrun)
  }
  @actions %{
    "candidate" => %{"propose" => "proposed", "reject" => "rejected", "supersede" => "superseded"},
    "requirement" => %{
      "draft" => "draft",
      "submit" => "pending_approval",
      "approve" => "approved",
      "reject" => "rejected",
      "supersede" => "superseded"
    },
    "assumption" => %{
      "open" => "open",
      "attest" => "attested",
      "test" => "tested",
      "discharge" => "discharged",
      "invalidate" => "invalidated",
      "supersede" => "superseded"
    }
  }

  @required %{
    "candidate" =>
      ~w(schema_version id revision status question rationale counterhypothesis uncertainty gaps source_refs scope events context),
    "requirement" =>
      ~w(schema_version id revision status statement owner scope behavior_refs assumptions events),
    "assumption" =>
      ~w(schema_version id revision status statement category owner scope evidence gaps events),
    "obligation" =>
      ~w(schema_version id revision status requirement property kind scope source_refs assumptions preconditions witness precondition_challenges open_gaps created_at)
  }
  @optional %{
    "candidate" => ~w(superseded_by),
    "requirement" => ~w(source_candidate_id superseded_by),
    "assumption" => ~w(superseded_by),
    "obligation" => []
  }

  @doc "Validate a G03 v2 record using an explicit string record kind."
  @spec validate(binary(), term()) :: {:ok, map()} | {:error, term()}
  def validate(kind, record) when kind in @kinds and is_map(record) do
    allowed = @required[kind] ++ @optional[kind]

    errors =
      Enum.flat_map(@required[kind], fn key ->
        if Map.has_key?(record, key), do: [], else: ["missing #{key}"]
      end) ++
        Enum.flat_map(Map.keys(record), fn key ->
          if key in allowed, do: [], else: ["unexpected #{inspect(key)}"]
        end)

    cond do
      errors != [] -> {:error, {:invalid_g03_record, kind, Enum.sort(errors)}}
      not valid_common?(kind, record) -> {:error, {:invalid_g03_record, kind, :common_fields}}
      not valid_body?(kind, record) -> {:error, {:invalid_g03_record, kind, :body_fields}}
      true -> {:ok, record}
    end
  end

  def validate(kind, _), do: {:error, {:invalid_g03_record, kind, :unsupported_kind_or_object}}

  @doc "Validate the source scope and its distinct versioned references."
  def reference?(ref) when is_map(ref) do
    schema =
      case ref["schema_version"] do
        1 -> "behavior_ref"
        2 -> "behavior_ref_v2"
        _ -> "unsupported"
      end

    match?({:ok, _}, Core.validate(schema, ref)) and
      ref["upstream_schema_version"] == ref["schema_version"]
  end

  def reference?(_), do: false

  def scope?(
        %{
          "project_id" => project,
          "snapshot_id" => snapshot,
          "upstream_schema_version" => version
        } = scope
      ) do
    map_size(scope) == 3 and is_binary(project) and byte_size(project) > 0 and
      ((version == 1 and Core.valid_id?(snapshot)) or
         (version == 2 and is_binary(snapshot) and
            Regex.match?(~r/\A[0-9a-f]{64}\z/, snapshot)))
  end

  def scope?(_), do: false

  def within_scope?(ref, scope) do
    reference?(ref) and scope?(scope) and ref["project_id"] == scope["project_id"] and
      ref["snapshot_id"] == scope["snapshot_id"] and
      ref["upstream_schema_version"] == scope["upstream_schema_version"]
  end

  @doc "Check immutable contiguous revisions and allowed lifecycle status changes."
  def transition(kind, nil, record) when kind in @kinds do
    first_action = %{
      "candidate" => "propose",
      "requirement" => "draft",
      "assumption" => "open"
    }

    if record["revision"] == 1 and
         (kind == "obligation" or last_action(record) == first_action[kind]) do
      :ok
    else
      {:error, :invalid_initial_lifecycle_event}
    end
  end

  def transition(kind, previous, record) when kind in @kinds and is_map(previous) do
    valid =
      contiguous_revision?(previous, record) and
        kind != "obligation" and
        revision_allowed?(kind, previous["status"], record["status"]) and
        Enum.take(record["events"], -1) != [] and
        Enum.drop(record["events"], -1) == previous["events"] and
        same_immutable_fields?(kind, previous, record)

    if valid, do: :ok, else: {:error, :invalid_lifecycle_transition}
  end

  def transition(_, _, _), do: {:error, :invalid_lifecycle_transition}

  defp revision_allowed?("candidate", "proposed", next), do: next in ~w(rejected superseded)
  defp revision_allowed?("requirement", "draft", "pending_approval"), do: true

  defp revision_allowed?("requirement", "pending_approval", next),
    do: next in ~w(approved rejected)

  defp revision_allowed?("requirement", "approved", "superseded"), do: true

  defp revision_allowed?("assumption", "open", next),
    do: next in ~w(attested tested invalidated superseded)

  defp revision_allowed?("assumption", "attested", next),
    do: next in ~w(tested invalidated superseded)

  defp revision_allowed?("assumption", "tested", next),
    do: next in ~w(discharged invalidated superseded)

  defp revision_allowed?("assumption", "discharged", "superseded"), do: true
  defp revision_allowed?(_, _, _), do: false

  defp same_immutable_fields?("candidate", before, updated) do
    Enum.all?(
      ~w(question rationale counterhypothesis uncertainty gaps source_refs context),
      &(before[&1] == updated[&1])
    )
  end

  defp same_immutable_fields?("requirement", before, updated) do
    Enum.all?(
      ~w(statement owner behavior_refs assumptions source_candidate_id),
      &(before[&1] == updated[&1])
    )
  end

  defp same_immutable_fields?("assumption", before, updated) do
    Enum.all?(~w(statement category owner), &(before[&1] == updated[&1])) and
      Enum.all?(before["evidence"], &(&1 in updated["evidence"])) and
      Enum.all?(before["gaps"], &(&1 in updated["gaps"]))
  end

  defp same_immutable_fields?(_, _, _), do: false

  defp valid_common?(kind, record) do
    record["schema_version"] == 2 and Core.valid_id?(record["id"]) and
      Core.positive?(record["revision"]) and record["revision"] <= 512 and
      record["status"] in @statuses[kind] and scope?(record["scope"])
  end

  defp valid_body?("candidate", r) do
    Enum.all?(~w(question rationale counterhypothesis uncertainty), &Core.nonempty?(r[&1])) and
      Core.text_list?(r["gaps"]) and r["gaps"] != [] and refs?(r["source_refs"], r["scope"], true) and
      context?(r["context"]) and
      events?("candidate", r) and superseded?(r)
  end

  defp valid_body?("requirement", r) do
    Core.nonempty?(r["statement"]) and Core.nonempty?(r["owner"]) and
      refs?(r["behavior_refs"], r["scope"], false) and
      revisions?(r["assumptions"]) and events?("requirement", r) and
      optional_id?(r, "source_candidate_id") and superseded?(r) and
      (r["status"] != "approved" or r["behavior_refs"] != [])
  end

  defp valid_body?("assumption", r) do
    Core.nonempty?(r["statement"]) and Core.nonempty?(r["owner"]) and
      r["category"] in ~w(external compiler model runtime) and
      Core.text_list?(r["gaps"]) and evidence_list?(r["evidence"], r["scope"]) and
      events?("assumption", r) and superseded?(r) and
      (r["status"] != "discharged" or Enum.any?(r["evidence"], &(&1["kind"] in ~w(test analysis))))
  end

  defp valid_body?("obligation", r) do
    obligation_identity?(r) and
      refs?(r["source_refs"], r["scope"], true) and revisions?(r["assumptions"]) and
      obligation_premises?(r) and
      Core.text_list?(r["open_gaps"]) and timestamp?(r["created_at"]) and
      (r["witness"]["status"] != "missing" or
         Enum.any?(r["precondition_challenges"], &(&1["kind"] == "witness_missing")))
  end

  defp contiguous_revision?(previous, record) do
    record["id"] == previous["id"] and
      record["revision"] == previous["revision"] + 1 and
      record["scope"] == previous["scope"]
  end

  defp context?(c) when is_map(c) do
    Enum.sort(Map.keys(c)) == ~w(motif query_receipt source_mode) and
      c["source_mode"] == "source_only" and
      (is_nil(c["motif"]) or Core.nonempty?(c["motif"])) and
      (is_nil(c["query_receipt"]) or is_map(c["query_receipt"]))
  end

  defp context?(_), do: false

  defp evidence_list?(evidence, scope) do
    is_list(evidence) and length(evidence) <= 128 and
      Enum.all?(evidence, &evidence?(&1, scope)) and evidence == Enum.uniq(evidence)
  end

  defp obligation_identity?(r) do
    r["revision"] == 1 and r["status"] == "unrun" and
      ref_revision?(r["requirement"]) and Core.nonempty?(r["property"]) and
      r["kind"] in ~w(other exunit property conformance lynx lean veil tlc quint)
  end

  defp obligation_premises?(r) do
    Core.text_list?(r["preconditions"]) and r["preconditions"] != [] and
      witness?(r["witness"], r["scope"]) and challenges?(r["precondition_challenges"])
  end

  defp event_identity?("candidate", "propose", _, "untrusted_proposer"), do: true

  defp event_identity?(_, _, actor, identity) do
    String.starts_with?(actor, "human:") and byte_size(actor) > 6 and
      identity == "self_attested_not_authenticated"
  end

  defp refs?(refs, scope, required) do
    is_list(refs) and length(refs) <= 128 and (not required or refs != []) and
      Enum.all?(refs, &within_scope?(&1, scope)) and refs == Enum.uniq(refs)
  end

  defp revisions?(refs) when is_list(refs) do
    length(refs) <= 128 and Enum.all?(refs, &ref_revision?/1) and refs == Enum.uniq(refs)
  end

  defp revisions?(_), do: false

  defp ref_revision?(%{"id" => id, "revision" => rev} = value) do
    map_size(value) == 2 and Core.valid_id?(id) and Core.positive?(rev)
  end

  defp ref_revision?(_), do: false

  defp evidence?(
         %{"kind" => kind, "description" => description, "source_refs" => refs} = e,
         scope
       ) do
    map_size(e) == 3 and kind in ~w(attestation test analysis source) and
      Core.nonempty?(description) and refs?(refs, scope, false)
  end

  defp evidence?(_, _), do: false

  defp witness?(
         %{"status" => status, "description" => description, "source_refs" => refs} = w,
         scope
       ) do
    map_size(w) == 3 and status in ~w(missing documented challenged) and
      Core.nonempty?(description) and refs?(refs, scope, false)
  end

  defp witness?(_, _), do: false

  defp challenges?(v) when is_list(v) do
    length(v) <= 128 and
      Enum.all?(v, fn
        %{"kind" => kind, "statement" => statement} = c ->
          map_size(c) == 2 and kind in ~w(witness_missing vacuity contradiction unknown) and
            Core.nonempty?(statement)

        _ ->
          false
      end) and v == Enum.uniq(v)
  end

  defp challenges?(_), do: false

  defp events?(kind, r) do
    events = r["events"]

    is_list(events) and length(events) == r["revision"] and
      Enum.all?(Enum.with_index(events, 1), fn {event, revision} ->
        audit_event?(kind, event, revision)
      end) and
      Map.get(@actions[kind], last_action(r)) == r["status"]
  end

  defp audit_event?(
         kind,
         %{
           "action" => action,
           "actor" => actor,
           "at" => at,
           "revision" => revision,
           "identity_assurance" => identity
         } = e,
         rev
       ) do
    map_size(e) == 5 and revision == rev and Map.has_key?(@actions[kind], action) and
      Core.nonempty?(actor) and byte_size(actor) <= 160 and timestamp?(at) and
      event_identity?(kind, action, actor, identity)
  end

  defp audit_event?(_, _, _), do: false

  defp last_action(%{"events" => events}) when is_list(events) and events != [] do
    List.last(events)["action"]
  end

  defp last_action(_), do: nil

  defp optional_id?(r, field), do: not Map.has_key?(r, field) or Core.valid_id?(r[field])

  defp superseded?(r) do
    if r["status"] == "superseded" do
      Core.valid_id?(r["superseded_by"]) and r["superseded_by"] != r["id"]
    else
      not Map.has_key?(r, "superseded_by")
    end
  end

  defp timestamp?(value) when is_binary(value) do
    match?({:ok, _, _}, DateTime.from_iso8601(value))
  end

  defp timestamp?(_), do: false
end
