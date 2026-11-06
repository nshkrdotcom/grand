defmodule Grand.BeamCompass.Query do
  @moduledoc """
  Deterministic, bounded LOCAL read-only query of an imported v2 snapshot.

  This is not BeamCompass P03 projection, causal closure or runtime evidence.
  The budget bounds selected entity/relation records; evidence dependencies and
  omission/uncertainty receipts are reported separately, never silently dropped.
  """

  alias Grand.BeamCompass.V2

  @lenses ~w(neighbors connected effects)
  @effect_rels ~w(sends may_deliver_to describes_effect performs_effect)
  @max_budget 256
  @max_preserve 128

  @doc "Query by :focus entity ID, :lens, :budget and typed :preserve entries."
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(snapshot, opts) when is_list(opts) do
    with {:ok, env} <- V2.validate_envelope(snapshot),
         {:ok, request} <- validate_request(env["upstream"], opts) do
      upstream = env["upstream"]
      relations = Map.new(upstream["relations"], &{&1["id"], &1})
      focus = request["focus"]
      preserve = request["preserve"]
      {essential_entities, essential_relations} = essentials(focus, preserve, relations)
      required_count = MapSet.size(essential_entities) + MapSet.size(essential_relations)

      if required_count > request["budget"] do
        {:error, {:preservation_budget_exceeded, required_count, request["budget"]}}
      else
        {kept_entities, kept_relations} =
          select(upstream["relations"], essential_entities, essential_relations, request)

        {:ok,
         response(
           env,
           request,
           kept_entities,
           kept_relations,
           essential_entities,
           essential_relations
         )}
      end
    end
  end

  def run(_, _), do: {:error, :invalid_query_arguments}

  defp validate_request(upstream, opts) do
    focus = Keyword.get(opts, :focus)
    lens = Keyword.get(opts, :lens, "neighbors")
    budget = Keyword.get(opts, :budget, 32)
    preserve = Keyword.get(opts, :preserve, [])
    entities = MapSet.new(Enum.map(upstream["entities"], & &1["id"]))
    relations = MapSet.new(Enum.map(upstream["relations"], & &1["id"]))

    cond do
      not is_binary(focus) or not MapSet.member?(entities, focus) ->
        {:error, {:unresolved_focus_entity, focus}}

      lens not in @lenses ->
        {:error, {:unsupported_local_query_lens, lens}}

      not is_integer(budget) or budget < 1 or budget > @max_budget ->
        {:error, {:invalid_query_budget, budget, @max_budget}}

      not is_list(preserve) or length(preserve) > @max_preserve ->
        {:error, :invalid_preserve_list}

      not Enum.all?(preserve, &valid_preserve?/1) ->
        {:error, :invalid_preserve_reference}

      length(Enum.uniq(preserve)) != length(preserve) ->
        {:error, :duplicate_preserve_reference}

      true ->
        unknown =
          Enum.reject(preserve, fn ref ->
            if ref["object_kind"] == "entity",
              do: MapSet.member?(entities, ref["object_id"]),
              else: MapSet.member?(relations, ref["object_id"])
          end)

        if unknown == [] do
          {:ok,
           %{
             "focus" => focus,
             "lens" => lens,
             "budget" => budget,
             "preserve" => Enum.sort_by(preserve, &{&1["object_kind"], &1["object_id"]})
           }}
        else
          {:error, {:unresolved_preserve_references, unknown}}
        end
    end
  end

  defp valid_preserve?(%{"object_kind" => kind, "object_id" => id} = ref) do
    map_size(ref) == 2 and kind in ~w(entity relation) and is_binary(id) and byte_size(id) > 0
  end

  defp valid_preserve?(_), do: false

  defp essentials(focus, preserve, relations) do
    Enum.reduce(preserve, {MapSet.new([focus]), MapSet.new()}, fn ref, {entity_ids, relation_ids} ->
      case ref do
        %{"object_kind" => "entity", "object_id" => id} ->
          {MapSet.put(entity_ids, id), relation_ids}

        %{"object_kind" => "relation", "object_id" => id} ->
          r = Map.fetch!(relations, id)
          endpoints = Enum.reject([r["source_id"], r["target_id"]], &is_nil/1)
          {Enum.reduce(endpoints, entity_ids, &MapSet.put(&2, &1)), MapSet.put(relation_ids, id)}
      end
    end)
  end

  defp select(all_relations, entity_ids, relation_ids, request) do
    {updated_entities, updated_relations} =
      Enum.reduce(all_relations, {entity_ids, relation_ids}, fn relation, {entities, relations} ->
        if eligible?(relation, request, entities) and not MapSet.member?(relations, relation["id"]) do
          endpoints = Enum.reject([relation["source_id"], relation["target_id"]], &is_nil/1)
          candidate_entities = Enum.reduce(endpoints, entities, &MapSet.put(&2, &1))
          proposed_count = MapSet.size(candidate_entities) + MapSet.size(relations) + 1

          if proposed_count <= request["budget"] do
            {candidate_entities, MapSet.put(relations, relation["id"])}
          else
            {entities, relations}
          end
        else
          {entities, relations}
        end
      end)

    if request["lens"] == "connected" and
         MapSet.size(updated_relations) > MapSet.size(relation_ids) and
         MapSet.size(updated_entities) + MapSet.size(updated_relations) < request["budget"] do
      select(all_relations, updated_entities, updated_relations, request)
    else
      {updated_entities, updated_relations}
    end
  end

  defp eligible?(r, %{"lens" => "neighbors", "focus" => focus}, _entities),
    do: touches?(r, focus)

  defp eligible?(r, %{"lens" => "effects", "focus" => focus}, _entities),
    do: touches?(r, focus) and r["kind"] in @effect_rels

  defp eligible?(r, %{"lens" => "connected"}, entity_ids),
    do: MapSet.member?(entity_ids, r["source_id"]) or MapSet.member?(entity_ids, r["target_id"])

  defp touches?(r, id), do: r["source_id"] == id or r["target_id"] == id

  defp response(env, request, kept_entities, kept_relations, required_entities, required_relations) do
    upstream = env["upstream"]
    selected_entities = Enum.filter(upstream["entities"], &MapSet.member?(kept_entities, &1["id"]))
    selected_relations = Enum.filter(upstream["relations"], &MapSet.member?(kept_relations, &1["id"]))
    evidence_map = Map.new(upstream["evidence"], &{&1["id"], &1})
    seeds = Enum.flat_map(selected_entities ++ selected_relations, & &1["evidence_ids"])
    evidence_ids = evidence_closure(seeds, evidence_map, MapSet.new())
    selected_evidence = Enum.filter(upstream["evidence"], &MapSet.member?(evidence_ids, &1["id"]))

    omissions =
      Enum.flat_map(upstream["entities"], fn e ->
        if MapSet.member?(kept_entities, e["id"]),
          do: [],
          else: [omitted("entity", e["id"], "outside_retained_frontier_or_budget")]
      end) ++
        Enum.flat_map(upstream["relations"], fn r ->
          if MapSet.member?(kept_relations, r["id"]),
            do: [],
            else: [omitted("relation", r["id"], omission_reason(r, request))]
        end) ++
        Enum.flat_map(upstream["evidence"], fn e ->
          if MapSet.member?(evidence_ids, e["id"]),
            do: [],
            else: [omitted("evidence", e["id"], "no_retained_claim_requires_evidence")]
        end)

    preserved =
      Enum.map(upstream["entities"], fn e ->
        if MapSet.member?(required_entities, e["id"]),
          do: %{"object_kind" => "entity", "object_id" => e["id"]},
          else: nil
      end) ++
        Enum.map(upstream["relations"], fn r ->
          if MapSet.member?(required_relations, r["id"]),
            do: %{"object_kind" => "relation", "object_id" => r["id"]},
            else: nil
        end)

    unresolved =
      upstream["relations"]
      |> Enum.filter(&(&1["resolution"] != "resolved"))
      |> Enum.map(fn r ->
        %{
          "relation_id" => r["id"],
          "resolution" => r["resolution"],
          "epistemic_status" => r["epistemic_status"],
          "target_id" => r["target_id"],
          "retained" => MapSet.member?(kept_relations, r["id"])
        }
      end)

    preserved = Enum.reject(preserved, &is_nil/1)
    selected_counts = counts(selected_entities, selected_relations, selected_evidence)

    %{
      "format" => "grand.local_query.v1",
      "schema_version" => 1,
      "project_id" => env["project_id"],
      "snapshot_id" => env["snapshot_id"],
      "source_digest" => upstream["manifest"]["source_digest"],
      "epistemic_scope" => "source_only_no_runtime_or_causal_claim",
      "request" => request,
      "entities" => selected_entities,
      "relations" => selected_relations,
      "evidence" => selected_evidence,
      "issues" => upstream["issues"],
      "limitations" => upstream["limitations"] ++ ["Local bounded Grand query, not an upstream P03 projection or a proof"],
      "receipt" => %{
        "preserved" => preserved,
        "omitted" => omissions,
        "unresolved" => unresolved,
        "selected_counts" => selected_counts,
        "snapshot_counts" => counts(upstream["entities"], upstream["relations"], upstream["evidence"]),
        "omitted_count" => length(omissions),
        "unresolved_count" => length(unresolved),
        "selected_graph_complete" => omissions == [] and unresolved == [],
        "semantic_completeness" => "not_claimed"
      }
    }
  end

  defp evidence_closure([], _evidence, found), do: found

  defp evidence_closure([id | rest], evidence, found) do
    if MapSet.member?(found, id) do
      evidence_closure(rest, evidence, found)
    else
      evidence_closure(evidence[id]["input_evidence_ids"] ++ rest, evidence, MapSet.put(found, id))
    end
  end

  defp omission_reason(r, %{"lens" => "effects"} = request) do
    if r["kind"] not in @effect_rels,
      do: "excluded_by_effects_lens",
      else: omission_reason(r, Map.put(request, "lens", "neighbors"))
  end

  defp omission_reason(r, %{"lens" => "neighbors", "focus" => focus}) do
    if touches?(r, focus), do: "budget_excluded", else: "outside_one_hop_focus"
  end

  defp omission_reason(_r, _request), do: "outside_retained_frontier_or_budget"

  defp omitted(kind, id, reason),
    do: %{"object_kind" => kind, "object_id" => id, "reason" => reason}

  defp counts(entities, relations, evidence),
    do: %{"entities" => length(entities), "relations" => length(relations), "evidence" => length(evidence)}
end
