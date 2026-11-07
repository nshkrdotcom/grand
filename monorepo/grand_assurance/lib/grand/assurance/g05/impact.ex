defmodule Grand.Assurance.G05.Impact do
  @moduledoc """
  Conservative syntactic source-only v1/v2 snapshot comparison and reverse
  dependency links. No invented semantic diff, stable cross-revision identity,
  runtime causality or mandatory upstream P04 export. Unmatched moves remain
  unresolved unless independent same-body and stable semantic-key evidence
  support only a *probable* correspondence, never a proven equivalence.
  """

  @allowed_versions [1, 2]

  @doc "Compare two portable source-only snapshots and explicit G03 links."
  @spec compare(map(), map(), list(), keyword()) :: {:ok, map()} | {:error, term()}
  def compare(before, after, links, opts \\ []) do
    with {:ok, first, from_id, version} <- snapshot(before),
         {:ok, last, to_id, ^version} <- snapshot(after),
         :ok <- validate_links(links) do
      from_ids = Map.keys(first) |> MapSet.new()
      to_ids = Map.keys(last) |> MapSet.new()
      common = MapSet.intersection(from_ids, to_ids) |> MapSet.to_list()
      deleted = MapSet.difference(from_ids, to_ids) |> MapSet.to_list()
      added = MapSet.difference(to_ids, from_ids) |> MapSet.to_list()

      exact_changes = Enum.flat_map(common, fn id ->
        old = Map.fetch!(first, id)
        new = Map.fetch!(last, id)
        cond do
          old == new -> []
          strip_position(old) == strip_position(new) ->
            [change("unresolved", id, "line_or_column_only; identity requires review")]
          true -> [change("modified", id, "same id, changed source-only object")]
        end
      end)

      matches = probable_matches(deleted, added, first, last)
      paired_old = Enum.map(matches, & &1["from"]) |> MapSet.new()
      paired_new = Enum.map(matches, & &1["to"]) |> MapSet.new()

      changes =
        exact_changes ++
          Enum.map(deleted, fn id -> change("removed", id, "not present in later source snapshot") end) ++
          Enum.map(added, fn id -> change("added", id, "not present in earlier source snapshot") end)

      impacted = MapSet.new(for c <- changes, c["kind"] != "added", do: c["object_id"])
      impacted = dependent_objects(impacted, first, last)
      uncertain = Enum.any?(changes, &(&1["kind"] == "unresolved")) or
        Enum.any?(deleted, &(!MapSet.member?(paired_old, &1))) or
        Enum.any?(added, &(!MapSet.member?(paired_new, &1)))
      graph = reverse_links(links)
      linked = Enum.filter(links, fn link ->
        uncertain or Enum.any?(link["source_refs"], fn ref ->
          MapSet.member?(impacted, reference_id(ref))
        end)
      end)
      unresolved =
        for c <- changes, c["kind"] == "unresolved", do: c["object_id"]
      unresolved =
        unresolved ++ for id <- deleted, !MapSet.member?(paired_old, id), do: id
      unresolved = Enum.uniq(Enum.sort(unresolved))
      status =
        cond do
          changes == [] -> "unaffected"
          uncertain -> "unresolved"
          linked != [] -> "stale"
          true -> "unaffected"
        end

      {:ok, %{
        "format" => "grand.g05.impact", "schema_version" => 2,
        "id" => Keyword.get(opts, :id, "G05-source-only-impact"),
        "from_snapshot_id" => from_id, "to_snapshot_id" => to_id,
        "upstream_schema_version" => version,
        "classification" => "syntactic_source_only_no_semantic_diff_export",
        "changes" => Enum.sort_by(changes, &{&1["object_id"], &1["kind"]}),
        "probable_matches" => matches,
        "affected_requirements" => linked |> Enum.map(& &1["requirement"]["id"]) |> Enum.uniq() |> Enum.sort(),
        "affected_obligations" => linked |> Enum.map(& &1["obligation_id"]) |> Enum.uniq() |> Enum.sort(),
        "affected_results" => linked |> Enum.flat_map(& &1["result_ids"]) |> Enum.uniq() |> Enum.sort(),
        "unresolved_mappings" => unresolved,
        "reverse_links" => graph,
        "evidence_status" => status,
        "revisit" => if(changes == [], do: [], else: ["review source/requirement link", "re-run affected law or model before asserting current"])
      }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :different_or_invalid_snapshot_versions}
    end
  end

  @doc "Reverse links retain the source -> requirement -> obligation -> run chain."
  @spec reverse_links(list()) :: map()
  def reverse_links(links) do
    Enum.reduce(links, %{}, fn link, acc ->
      path = %{
        "requirement" => link["requirement"],
        "obligation_id" => link["obligation_id"],
        "result_ids" => link["result_ids"],
        "assumptions" => link["assumptions"],
        "model_files" => link["model_files"]
      }
      sources = Enum.map(link["source_refs"], &reference_id/1)
      assumptions = Enum.map(link["assumptions"], fn ref ->
        "assumption:#{ref["id"]}@#{ref["revision"]}"
      end)
      models = Enum.map(link["model_files"], &"model:#{&1}")
      requirement = link["requirement"]
      paths =
        for id <- Enum.uniq(sources ++ assumptions ++ models ++ [
          "requirement:#{requirement["id"]}@#{requirement["revision"]}",
          "obligation:#{link["obligation_id"]}"
        ]), do: {id, path}

      Enum.reduce(paths, acc, fn {key, path}, output ->
        Map.update(output, key, [path], &[path | &1])
      end)
    end)
    |> Enum.into(%{}, fn {id, paths} -> {id, Enum.reverse(paths)} end)
  end

  defp snapshot(%{"schema_version" => v} = data) when v in @allowed_versions do
    {collections, id} =
      case v do
        1 -> {[{"fact", data["facts"]}], data["id"]}
        2 -> {[{"entity", data["entities"]}, {"relation", data["relations"]},
               {"evidence", data["evidence"]}], data["snapshot_id"]}
      end

    entries = Enum.flat_map(collections, fn {kind, values} ->
      if is_list(values) do
        Enum.map(values, fn object -> {kind, object} end)
      else
        [{kind, nil}]
      end
    end)

    if is_binary(id) and id != "" and
         Enum.all?(entries, fn {_kind, object} -> is_map(object) and is_binary(object["id"]) end) and
         (entries |> Enum.map(fn {_, object} -> object["id"] end) |> Enum.uniq() |> length()) == length(entries) do
      records = Map.new(entries, fn {kind, object} -> {object["id"], Map.put(object, "_collection", kind)} end)
      {:ok, records, id, v}
    else
      {:error, :invalid_source_only_snapshot}
    end
  end

  defp snapshot(%{"schema_version" => version}) when is_integer(version),
    do: {:error, :unsupported_upstream_version}
  defp snapshot(_), do: {:error, :invalid_source_only_snapshot}

  defp change(kind, id, reason), do: %{"kind" => kind, "object_id" => id, "reason" => reason}

  defp probable_matches(deleted, added, before, after) do
    for id <- deleted,
        old = Map.fetch!(before, id),
        key = old["semantic_key"],
        is_binary(key) and key != "",
        candidates = Enum.filter(added, fn candidate ->
          new = Map.fetch!(after, candidate)
          new["semantic_key"] == key and
            new["_collection"] == old["_collection"] and
            Map.drop(strip_position(new), ["id", "evidence_ids"]) ==
              Map.drop(strip_position(old), ["id", "evidence_ids"])
        end),
        length(candidates) == 1 do
      %{"from" => id, "to" => hd(candidates), "confidence" => "probable_not_verified",
        "reason" => "unique stable semantic_key and location-insensitive source-only content"}
    end
  end

  # A change to evidence or a source-only relation can invalidate a linked
  # entity/function as well. This graph is conservative syntax, not call-graph
  # proof or a claim that a runtime edge actually fired.
  defp dependent_objects(changed, before, after) do
    expand_dependencies(changed, Map.values(before) ++ Map.values(after))
  end

  defp expand_dependencies(changed, objects) do
    found = Enum.reduce(objects, changed, fn object, seen ->
      evidence = Map.get(object, "evidence_ids", [])
      from_evidence =
        is_list(evidence) and Enum.any?(evidence, &MapSet.member?(seen, &1))
      from_relation =
        Enum.any?([object["source_id"], object["target_id"]], fn id ->
          is_binary(id) and MapSet.member?(seen, id)
        end)
      if from_evidence or from_relation, do: MapSet.put(seen, object["id"]), else: seen
    end)

    if MapSet.size(found) == MapSet.size(changed) do
      found
    else
      expand_dependencies(found, objects)
    end
  end

  defp strip_position(term) when is_map(term) do
    Enum.into(term, %{}, fn {key, value} ->
      {key, if(key == "anchor" and is_map(value),
        do: Map.drop(value, ["line", "column"]), else: strip_position(value))}
    end)
  end
  defp strip_position(term) when is_list(term), do: Enum.map(term, &strip_position/1)
  defp strip_position(term), do: term

  defp reference_id(%{"object_id" => id}), do: id
  defp reference_id(%{"fact_id" => id}), do: id
  defp reference_id(_), do: nil

  defp validate_links(links) when is_list(links) do
    if Enum.all?(links, fn link ->
      is_map(link) and is_map(link["requirement"]) and
        is_binary(link["requirement"]["id"]) and is_binary(link["obligation_id"]) and
        is_list(link["source_refs"]) and
        Enum.all?(link["source_refs"], &(is_binary(reference_id(&1)))) and
        is_list(link["result_ids"]) and Enum.all?(link["result_ids"], &is_binary/1) and
        is_list(link["assumptions"]) and
        Enum.all?(link["assumptions"], fn ref ->
          is_map(ref) and is_binary(ref["id"]) and
            is_integer(ref["revision"]) and ref["revision"] > 0
        end) and
        is_integer(link["requirement"]["revision"]) and
        link["requirement"]["revision"] > 0 and
        is_list(link["model_files"]) and
        Enum.all?(link["model_files"], &is_binary/1)
    end), do: :ok, else: {:error, :invalid_impact_links}
  end
  defp validate_links(_), do: {:error, :invalid_impact_links}
end
