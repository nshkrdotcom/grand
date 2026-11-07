defmodule Grand.BeamCompass.Motif do
  @moduledoc """
  Bounded deterministic *question generator* from v2 SOURCE-ONLY JSON facts.
  Requires an explicitly retry-labelled function with a typed resolved
  performs_effect relation to a syntactic effect in the SAME snapshot.
  No runtime reachability, loop, remote side effect, causality, identity or bug
  is inferred. Other relation performers/omissions remain in the query receipt.
  """

  alias Grand.BeamCompass.{Query, V2}

  @doc "Return proposed candidate attributes, never an approved requirement."
  def retry_external_effect(snapshot) do
    with {:ok, envelope} <- V2.validate_envelope(snapshot),
         {:ok, {function, relation, effect}} <- motif(envelope["upstream"]),
         {:ok, query} <-
           Query.run(envelope,
             focus: function["id"],
             lens: "effects",
             budget: 16,
             preserve: [%{"object_kind" => "relation", "object_id" => relation["id"]}]
           ),
         {:ok, refs} <- references(envelope, function, relation, effect) do
      hash =
        :crypto.hash(:sha256, envelope["snapshot_id"] <> function["id"] <> relation["id"])
        |> Base.encode16(case: :lower)

      scope = %{
        "project_id" => envelope["project_id"],
        "snapshot_id" => envelope["snapshot_id"],
        "upstream_schema_version" => 2
      }

      {:ok,
       %{
         "id" => "g03-motif-" <> String.slice(hash, 0, 24),
         "question" => "Could retries of the labelled function cause a repeated external effect?",
         "rationale" =>
           "Same-snapshot source labels include a retry-marked function and a typed " <>
             "performs_effect relation to an effect site; this is a syntactic association only.",
         "counterhypothesis" =>
           "The retry label may describe guarded/idempotent or unreachable code; " <>
             "the effect may not execute more than once or may not be external.",
         "uncertainty" =>
           "No executed retry, target reachability, remote confirmation, effect identity, " <>
             "or runtime causal path is established from these source facts.",
         "gaps" => [
           "No executed retry or effect witness",
           "No proof of runtime effect performer or deduplication",
           "Bounded query omissions and unresolved links require separate review"
         ],
         "source_refs" => refs,
         "scope" => scope,
         "context" => %{
           "motif" => "syntactic_retry_and_typed_effect",
           "source_mode" => "source_only",
           "query_receipt" => query["receipt"]
         }
       }}
    end
  end

  defp motif(upstream) do
    entities = Map.new(upstream["entities"], &{&1["id"], &1})

    pairs =
      Enum.flat_map(upstream["relations"], fn relation ->
        function = Map.get(entities, relation["source_id"])
        effect = Map.get(entities, relation["target_id"])

        if relation["kind"] == "performs_effect" and relation["resolution"] == "resolved" and
             retry_function?(function) and is_map(effect) and effect["kind"] == "effect" do
          [{function, relation, effect}]
        else
          []
        end
      end)

    case pairs do
      [] -> {:error, :unsupported_retry_effect_motif_no_source_link}
      [first | _] -> {:ok, first}
    end
  end

  defp retry_function?(function) do
    is_map(function) and function["kind"] == "function" and
      String.contains?(String.downcase(function["label"]), "retry")
  end

  defp references(envelope, function, relation, effect) do
    objects = [{"entity", function}, {"relation", relation}, {"entity", effect}]
    evidence = envelope["upstream"]["evidence"]
    ids = Enum.flat_map(objects, fn {_, object} -> object["evidence_ids"] end)
    evidence_objects = Enum.filter(evidence, &(&1["id"] in ids))
    all = objects ++ Enum.map(evidence_objects, &{"evidence", &1})

    Enum.reduce_while(all, {:ok, []}, fn {kind, object}, {:ok, refs} ->
      case V2.reference(envelope, kind, object["id"]) do
        {:ok, reference} -> {:cont, {:ok, [reference | refs]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, refs} -> {:ok, Enum.reverse(refs)}
      error -> error
    end
  end
end
