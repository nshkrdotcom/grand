defmodule Grand.Assurance.G03 do
  @moduledoc """
  Separate v2 normative lifecycle; legacy v1 records are never upgraded.
  `human:` plus `ack_human: true` is manual SELF-ATTESTATION, not identity
  authentication or production authorization. Agents may propose only.
  An injected resolver must validate every exact versioned source reference.
  """

  alias Grand.Core
  alias Grand.Core.LifecycleStore, as: Store

  @doc "Propose a contextual source question; never a normative requirement."
  def propose(root, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, actor, at} <- proposer(opts) do
      record = %{
        "schema_version" => 2,
        "id" => attrs["id"],
        "revision" => 1,
        "status" => "proposed",
        "question" => attrs["question"],
        "rationale" => attrs["rationale"],
        "counterhypothesis" => attrs["counterhypothesis"],
        "uncertainty" => attrs["uncertainty"],
        "gaps" => attrs["gaps"],
        "scope" => attrs["scope"],
        "source_refs" => attrs["source_refs"],
        "context" => Map.get(attrs, "context", default_context()),
        "events" => [event("propose", actor, at, 1, "untrusted_proposer")]
      }

      persist(root, "candidate", record, opts)
    end
  end

  def propose(_, _, _), do: {:error, :invalid_candidate_input}

  @doc "Reject or supersede the candidate via explicitly self-attested human review."
  def decide_candidate(root, id, action, opts \\ []) when action in ~w(reject supersede) do
    with {:ok, actor, at} <- reviewer(opts),
         {:ok, previous} <- Store.latest(root, "candidate", id) do
      previous
      |> next(action, actor, at)
      |> maybe_supersede(action, Keyword.get(opts, :replacement_id))
      |> then(&persist(root, "candidate", &1, opts))
    end
  end

  def decide_candidate(_, _, _, _), do: {:error, :unsupported_candidate_decision}

  @doc "Create explicitly human-authored draft; source candidates never call it."
  def draft_requirement(root, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, actor, at} <- reviewer(opts) do
      record = %{
        "schema_version" => 2,
        "id" => attrs["id"],
        "revision" => 1,
        "status" => "draft",
        "statement" => attrs["statement"],
        "owner" => attrs["owner"],
        "scope" => attrs["scope"],
        "behavior_refs" => attrs["behavior_refs"],
        "assumptions" => attrs["assumptions"],
        "events" => [event("draft", actor, at, 1)]
      }

      record = case Map.fetch(attrs, "source_candidate_id") do
        {:ok, id} -> Map.put(record, "source_candidate_id", id)
        :error -> record
      end

      persist(root, "requirement", record, opts)
    end
  end

  def draft_requirement(_, _, _), do: {:error, :invalid_requirement_input}

  @doc "Submit/approve/reject/supersede with a distinct immutable revision/event."
  def review_requirement(root, id, action, opts \\ [])
      when action in ~w(submit approve reject supersede) do
    with {:ok, actor, at} <- reviewer(opts),
         {:ok, previous} <- Store.latest(root, "requirement", id),
         :ok <- submission_guard(previous, action) do
      previous
      |> next(action, actor, at)
      |> maybe_supersede(action, Keyword.get(opts, :replacement_id))
      |> then(&persist(root, "requirement", &1, opts))
    end
  end

  def review_requirement(_, _, _, _), do: {:error, :unsupported_requirement_decision}

  @doc "Register an assumption without claiming evidence of external truth."
  def register_assumption(root, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, actor, at} <- reviewer(opts) do
      record = %{
        "schema_version" => 2,
        "id" => attrs["id"],
        "revision" => 1,
        "status" => "open",
        "statement" => attrs["statement"],
        "category" => attrs["category"],
        "owner" => attrs["owner"],
        "scope" => attrs["scope"],
        "evidence" => Map.get(attrs, "evidence", []),
        "gaps" => attrs["gaps"],
        "events" => [event("open", actor, at, 1)]
      }

      persist(root, "assumption", record, opts)
    end
  end

  def register_assumption(_, _, _), do: {:error, :invalid_assumption_input}

  @doc "Add evidence and transition assumption; attested is NEVER proved."
  def revise_assumption(root, id, action, opts \\ [])
      when action in ~w(attest test discharge invalidate supersede) do
    with {:ok, actor, at} <- reviewer(opts),
         {:ok, previous} <- Store.latest(root, "assumption", id),
         {:ok, evidence} <- evidence_option(opts) do
      previous
      |> next(action, actor, at)
      |> Map.update!("evidence", &(&1 ++ evidence))
      |> maybe_supersede(action, Keyword.get(opts, :replacement_id))
      |> then(&persist(root, "assumption", &1, opts))
    end
  end

  def revise_assumption(_, _, _, _), do: {:error, :unsupported_assumption_decision}

  @doc "Register an unrun obligation with explicit premises and witness challenge."
  def record_obligation(root, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, _actor, at} <- reviewer(opts) do
      record = %{
        "schema_version" => 2,
        "id" => attrs["id"],
        "revision" => 1,
        "status" => "unrun",
        "requirement" => attrs["requirement"],
        "property" => attrs["property"],
        "kind" => attrs["kind"],
        "scope" => attrs["scope"],
        "source_refs" => attrs["source_refs"],
        "assumptions" => attrs["assumptions"],
        "preconditions" => attrs["preconditions"],
        "witness" => attrs["witness"],
        "precondition_challenges" => attrs["precondition_challenges"],
        "open_gaps" => attrs["open_gaps"],
        "created_at" => at
      }

      persist(root, "obligation", record, opts)
    end
  end

  def record_obligation(_, _, _), do: {:error, :invalid_obligation_input}

  @doc "Conditional, unrun receipt retaining pinned and current assumption revisions."
  def receipt(root, obligation_id) do
    with {:ok, state} <- Store.read(root),
         {:ok, obligation} <- Store.latest(root, "obligation", obligation_id),
         {:ok, requirement} <- exact(state, "requirement", obligation["requirement"]),
         {:ok, assumptions} <- receipt_assumptions(state, obligation["assumptions"]) do
      gaps =
        (obligation["open_gaps"] ++
           Enum.flat_map(assumptions, fn a -> a["record"]["gaps"] ++ a["current"]["gaps"] end))
        |> Enum.uniq()
        |> Enum.sort()

      challenging =
        obligation["witness"]["status"] != "documented" or
          obligation["precondition_challenges"] != []

      {:ok,
       %{
         "format" => "grand.g03.conditional_receipt",
         "schema_version" => 2,
         "obligation" => obligation,
         "requirement" => requirement,
         "assumption_revisions" => assumptions,
         "conditional_on" => obligation["assumptions"],
         "open_gaps" => gaps,
         "witness_challenge" => %{
           "status" => obligation["witness"]["status"],
           "precondition_challenges" => obligation["precondition_challenges"],
           "feasibility" => "not_checked"
         },
         "eligibility" => if(challenging, do: "blocked_for_witness_review", else: "review_only"),
         "verification_result" => %{"status" => "unrun", "engine" => "none-not-invoked"},
         "coverage_summary" => %{"status" => "unassessed", "source_mode" => "source_only"},
         "guarantee" => "none_unrun_conditional_record_not_a_proof",
         "identity_assurance" => "manual_self_attestation_not_authenticated"
       }}
    end
  end

  def history(root, kind, id), do: Store.history(root, kind, id)
  def latest(root, kind, id), do: Store.latest(root, kind, id)

  defp receipt_assumptions(state, refs) do
    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      with {:ok, pinned} <- exact(state, "assumption", ref),
           versions when is_list(versions) <- get_in(state, ["assumption", ref["id"]]) do
        entry = %{"reference" => ref, "record" => pinned, "current" => List.last(versions)}
        {:cont, {:ok, [entry | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp exact(state, kind, %{"id" => id, "revision" => revision}) do
    case get_in(state, [kind, id]) do
      nil -> {:error, {:dangling_lifecycle_revision, kind, id, revision}}
      revisions ->
        case Enum.find(revisions, &(&1["revision"] == revision)) do
          nil -> {:error, {:dangling_lifecycle_revision, kind, id, revision}}
          record -> {:ok, record}
        end
    end
  end

  defp persist(root, kind, record, opts) do
    with {:ok, value} <- Core.G03.validate(kind, record),
         {:ok, _} <- Store.append(root, kind, value, Keyword.take(opts,
           [:resolve_source, :expected_head, :fault])) do
      {:ok, value}
    end
  end

  defp next(record, action, actor, at) do
    statuses = %{
      "submit" => "pending_approval", "approve" => "approved", "reject" => "rejected",
      "supersede" => "superseded", "attest" => "attested", "test" => "tested",
      "discharge" => "discharged", "invalidate" => "invalidated"
    }

    revision = record["revision"] + 1

    record
    |> Map.put("status", Map.fetch!(statuses, action))
    |> Map.put("revision", revision)
    |> Map.update!("events", &(&1 ++ [event(action, actor, at, revision)]))
  end

  defp maybe_supersede(record, "supersede", target), do: Map.put(record, "superseded_by", target)
  defp maybe_supersede(record, _, _), do: record

  defp submission_guard(record, "submit") do
    if record["behavior_refs"] == [],
      do: {:error, :submitted_requirement_needs_source_refs},
      else: :ok
  end

  defp submission_guard(_, _), do: :ok

  defp event(action, actor, at, revision, identity \\ "self_attested_not_authenticated") do
    %{"action" => action, "actor" => actor, "at" => at,
      "revision" => revision, "identity_assurance" => identity}
  end

  defp proposer(opts) do
    actor = Keyword.get(opts, :actor)
    at = Keyword.get(opts, :at, now())

    if Core.nonempty?(actor) and byte_size(actor) <= 160 and timestamp?(at),
      do: {:ok, actor, at},
      else: {:error, :invalid_candidate_proposer_or_time}
  end

  defp reviewer(opts) do
    actor = Keyword.get(opts, :actor)
    at = Keyword.get(opts, :at, now())

    if Keyword.get(opts, :ack_human) == true and is_binary(actor) and
         String.starts_with?(actor, "human:") and byte_size(actor) > 6 and
         byte_size(actor) <= 160 and timestamp?(at) do
      {:ok, actor, at}
    else
      {:error, :explicit_human_review_ack_required_not_authenticated}
    end
  end

  defp timestamp?(at) when is_binary(at), do: match?({:ok, _, _}, DateTime.from_iso8601(at))
  defp timestamp?(_), do: false
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp evidence_option(opts) do
    case Keyword.get(opts, :evidence, []) do
      evidence when is_list(evidence) -> {:ok, evidence}
      _ -> {:error, :invalid_assumption_evidence}
    end
  end

  defp default_context do
    %{"motif" => nil, "query_receipt" => nil, "source_mode" => "source_only"}
  end
end
