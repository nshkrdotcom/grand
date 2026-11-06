defmodule Grand.BeamCompass.V2 do
  @moduledoc """
  Strict consumer of the pinned BeamCompass P02B source-only snapshot v2 JSON.

  The upstream schema and canonical hashing rules are checked locally, without
  loading an upstream Elixir module or opening any source anchor. Imported JSON
  is immutable. No cross-revision semantic correspondence is inferred.
  """

  alias Grand.BeamCompass.V1
  alias Grand.Core
  alias Grand.Core.JSON
  alias Grand.Core.Store

  @sha ~r/\A[0-9a-f]{64}\z/
  @entity_kinds ~w(module function actor trigger state_holder transition effect_intent effect channel decision failure_boundary behavior)
  @relation_kinds ~w(implements handles owns_state calls sends may_deliver_to updates_state describes_effect performs_effect supervises may_restart occurs_before potentially_concurrent causally_related)
  @epistemic ~w(sourced derived proposed unresolved)
  @resolutions ~w(resolved possible unresolved)
  @effects_from ~w(function actor behavior transition)
  @top ~w(entities evidence format issues limitations manifest project_id relations schema_version snapshot_id)
  @manifest ~w(config_digest providers source_digest source_revision toolchain)
  @entity ~w(epistemic_status evidence_ids id kind label limitations semantic_key)
  @relation ~w(epistemic_status evidence_ids id kind rationale resolution source_id target_id)
  @evidence ~w(anchor basis id input_evidence_ids mode provider_id)
  @anchor ~w(end_column end_line path source_sha256 start_column start_line)
  @max_items 10_000
  @max_bytes 4_000_000

  @doc "Import previously decoded JSON and its exact original byte digest."
  def import_data(data, bytes, opts) when is_binary(bytes) and is_list(opts) do
    project = Keyword.get(opts, :project_id)

    with :ok <- project_input(project),
         :ok <- check(byte_size(bytes) <= @max_bytes, :oversized_import_bytes),
         {:ok, decoded} <- JSON.decode(bytes, max_bytes: @max_bytes),
         :ok <- check(decoded == data, :source_bytes_mismatch),
         {:ok, snapshot} <- validate_snapshot(data),
         :ok <- check(snapshot["project_id"] == project, :project_id_mismatch),
         {:ok, canonical} <- JSON.encode(snapshot) do
      {:ok,
       %{
         "format" => "grand.beamcompass.v2.import",
         "schema_version" => 2,
         "project_id" => project,
         "snapshot_id" => snapshot["snapshot_id"],
         "source_sha256" => digest(bytes),
         "canonical_sha256" => digest(canonical),
         "upstream" => snapshot,
         "epistemic_scope" => "source_only_no_runtime_claim"
       }}
    end
  end

  def import_data(_, _, _), do: {:error, :invalid_import_arguments}

  defp project_input(value) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp project_input(nil), do: {:error, :project_id_required}
  defp project_input(_), do: {:error, :invalid_project_id}

  @doc "Schema + semantic graph + sorted set + canonical snapshot ID validation."
  def validate_snapshot(%{"schema_version" => version}) when version != 2,
    do: {:error, {:unsupported_schema_version, version}}

  def validate_snapshot(snapshot) when is_map(snapshot) do
    with :ok <- check(keys?(snapshot, @top), :top_level_fields),
         :ok <- check(snapshot["schema_version"] == 2, :schema_version),
         :ok <- check(snapshot["format"] == "beamcompass.snapshot", :format),
         :ok <- check(nonempty?(snapshot["project_id"]), :project_id),
         :ok <- check(sha?(snapshot["snapshot_id"]), :snapshot_id),
         :ok <- validate_manifest(snapshot["manifest"]),
         :ok <- validate_collections(snapshot),
         :ok <- validate_graph(snapshot),
         {:ok, payload} <- JSON.encode(Map.delete(snapshot, "snapshot_id")),
         :ok <- check(digest(payload) == snapshot["snapshot_id"], :snapshot_digest_mismatch) do
      {:ok, snapshot}
    end
  end

  def validate_snapshot(_), do: {:error, {:invalid_v2_snapshot, :expected_object}}

  defp validate_manifest(m) do
    with :ok <- check(keys?(m, @manifest), :manifest_fields),
         :ok <-
           check(
             is_nil(m["source_revision"]) or nonempty?(m["source_revision"]),
             :source_revision
           ),
         :ok <- check(sha?(m["source_digest"]) and sha?(m["config_digest"]), :manifest_digests),
         :ok <- check(keys?(m["toolchain"], ~w(elixir otp)), :toolchain_fields),
         :ok <- check(Enum.all?(~w(elixir otp), &nonempty?(m["toolchain"][&1])), :toolchain),
         :ok <- check(collection?(m["providers"], &valid_provider?/1, 1), :providers),
         do: check(sorted_ids?(m["providers"]), :provider_order_or_duplicate)
  end

  defp valid_provider?(p) do
    keys?(p, ~w(id mode name trust_context version)) and
      Enum.all?(~w(id name version trust_context), &nonempty?(p[&1])) and
      p["mode"] == "source"
  end

  defp validate_collections(s) do
    with :ok <- check(collection?(s["entities"], &valid_entity?/1), :entities),
         :ok <- check(sorted_ids?(s["entities"]), :entity_order_or_duplicate),
         :ok <- check(collection?(s["relations"], &valid_relation?/1), :relations),
         :ok <- check(sorted_ids?(s["relations"]), :relation_order_or_duplicate),
         :ok <- check(collection?(s["evidence"], &valid_evidence?/1), :evidence),
         :ok <- check(sorted_ids?(s["evidence"]), :evidence_order_or_duplicate),
         :ok <- check(collection?(s["issues"], &valid_issue?/1), :issues),
         :ok <- check(sorted_issues?(s["issues"]), :issue_order_or_duplicate),
         do: check(strings?(s["limitations"]), :limitations)
  end

  defp valid_entity?(e) do
    keys?(e, @entity) and nonempty?(e["id"]) and e["kind"] in @entity_kinds and
      nonempty?(e["label"]) and (is_nil(e["semantic_key"]) or nonempty?(e["semantic_key"])) and
      e["epistemic_status"] in @epistemic and strings?(e["evidence_ids"], 1) and
      strings?(e["limitations"])
  end

  defp valid_relation?(r) do
    keys?(r, @relation) and nonempty?(r["id"]) and r["kind"] in @relation_kinds and
      nonempty?(r["source_id"]) and optional_string?(r["target_id"]) and
      r["resolution"] in @resolutions and r["epistemic_status"] in @epistemic and
      strings?(r["evidence_ids"], 1) and nonempty?(r["rationale"])
  end

  defp valid_evidence?(e) do
    keys?(e, @evidence) and nonempty?(e["id"]) and nonempty?(e["provider_id"]) and
      e["mode"] == "source" and nonempty?(e["basis"]) and
      strings?(e["input_evidence_ids"]) and valid_anchor?(e["anchor"])
  end

  defp valid_anchor?(a) do
    keys?(a, @anchor) and V1.valid_relative_path?(a["path"]) and
      sha?(a["source_sha256"]) and Core.positive?(a["start_line"]) and
      Core.positive?(a["start_column"]) and valid_end?(a)
  end

  defp valid_end?(%{"end_line" => nil, "end_column" => nil}), do: true

  defp valid_end?(%{"end_line" => line, "end_column" => col} = a) do
    Core.positive?(line) and Core.positive?(col) and
      (line > a["start_line"] or (line == a["start_line"] and col >= a["start_column"]))
  end

  defp valid_end?(_), do: false

  defp valid_issue?(i) do
    keys?(i, ~w(code evidence_ids message)) and nonempty?(i["code"]) and
      nonempty?(i["message"]) and strings?(i["evidence_ids"])
  end

  defp validate_graph(s) do
    entities = Map.new(s["entities"], &{&1["id"], &1})
    evidence = Map.new(s["evidence"], &{&1["id"], &1})
    providers = MapSet.new(Enum.map(s["manifest"]["providers"], & &1["id"]))
    evidence_ids = MapSet.new(Map.keys(evidence))

    with :ok <-
           check(
             Enum.all?(s["evidence"], &valid_evidence_link?(&1, providers, evidence_ids)),
             :evidence_links
           ),
         :ok <- check(acyclic?(evidence), :evidence_cycle),
         :ok <-
           check(
             Enum.all?(s["entities"], &subset?(&1["evidence_ids"], evidence_ids)),
             :entity_evidence_links
           ),
         :ok <-
           check(
             Enum.all?(s["relations"], &valid_relation_links?(&1, entities, evidence_ids)),
             :relation_links_or_type
           ),
         do:
           check(
             Enum.all?(s["issues"], &subset?(&1["evidence_ids"], evidence_ids)),
             :issue_evidence_links
           )
  end

  defp valid_evidence_link?(e, providers, ids) do
    MapSet.member?(providers, e["provider_id"]) and subset?(e["input_evidence_ids"], ids) and
      e["id"] not in e["input_evidence_ids"]
  end

  defp valid_relation_links?(r, entities, ids) do
    target = if is_binary(r["target_id"]), do: Map.get(entities, r["target_id"]), else: nil
    source = Map.get(entities, r["source_id"])

    not is_nil(source) and valid_resolution?(r, target) and
      valid_effect_type?(r["kind"], source, target) and subset?(r["evidence_ids"], ids)
  end

  defp valid_resolution?(%{"resolution" => "resolved"}, target), do: not is_nil(target)

  defp valid_resolution?(%{"resolution" => "possible", "target_id" => id}, target),
    do: is_nil(id) or not is_nil(target)

  defp valid_resolution?(%{"resolution" => "unresolved"} = r, _target),
    do: is_nil(r["target_id"]) and r["epistemic_status"] == "unresolved"

  defp valid_effect_type?(kind, source, target)
       when kind in ~w(performs_effect describes_effect) do
    expected = if kind == "performs_effect", do: "effect", else: "effect_intent"

    is_map(source) and source["kind"] in @effects_from and
      (is_nil(target) or target["kind"] == expected)
  end

  defp valid_effect_type?(_, _, _), do: true

  defp optional_string?(value), do: is_nil(value) or nonempty?(value)

  defp acyclic?(evidence) do
    Enum.reduce_while(Map.keys(evidence), {:ok, MapSet.new()}, fn id, {:ok, done} ->
      case visit(id, evidence, done, MapSet.new()) do
        {:ok, checked} -> {:cont, {:ok, checked}}
        :cycle -> {:halt, :cycle}
      end
    end) != :cycle
  end

  @spec visit(term(), map(), MapSet.t(), MapSet.t()) :: {:ok, MapSet.t()} | :cycle
  defp visit(id, evidence, done, path) do
    cond do
      MapSet.member?(path, id) ->
        :cycle

      MapSet.member?(done, id) ->
        {:ok, done}

      true ->
        next = MapSet.put(path, id)

        visit_children(evidence[id]["input_evidence_ids"], evidence, done, next)
        |> case do
          {:ok, visited} -> {:ok, MapSet.put(visited, id)}
          :cycle -> :cycle
        end
    end
  end

  defp visit_children(children, evidence, done, path) do
    Enum.reduce_while(children, {:ok, done}, fn child, {:ok, visited} ->
      case visit(child, evidence, visited, path) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        :cycle -> {:halt, :cycle}
      end
    end)
  end

  @doc "Validate a v2 immutable Grand storage envelope after reading it."
  def validate_envelope(env) when is_map(env) do
    with :ok <-
           check(
             keys?(
               env,
               ~w(canonical_sha256 epistemic_scope format project_id schema_version snapshot_id source_sha256 upstream)
             ),
             :envelope_fields
           ),
         :ok <-
           check(
             env["schema_version"] == 2 and env["format"] == "grand.beamcompass.v2.import",
             :envelope_format
           ),
         :ok <- check(env["epistemic_scope"] == "source_only_no_runtime_claim", :envelope_scope),
         :ok <-
           check(
             sha?(env["source_sha256"]) and sha?(env["canonical_sha256"]),
             :envelope_hash_fields
           ),
         {:ok, upstream} <- validate_snapshot(env["upstream"]),
         :ok <-
           check(
             env["project_id"] == upstream["project_id"] and
               env["snapshot_id"] == upstream["snapshot_id"],
             :envelope_identity
           ),
         {:ok, encoded} <- JSON.encode(upstream),
         :ok <- check(digest(encoded) == env["canonical_sha256"], :envelope_canonical_hash) do
      {:ok, env}
    end
  end

  def validate_envelope(_), do: {:error, {:invalid_v2_snapshot, :envelope_expected_object}}

  @doc "Store in a v2-only namespace to avoid v1 object/key collisions."
  def store(envelope, root) do
    with {:ok, env} <- validate_envelope(envelope),
         {:ok, key} <- storage_key(env["project_id"], env["snapshot_id"]) do
      Store.put(root, "snapshots_v2", key, env)
    end
  end

  def load(root, project, snapshot_id) do
    with {:ok, key} <- storage_key(project, snapshot_id),
         {:ok, envelope} <- Store.get(root, "snapshots_v2", key),
         {:ok, valid} <- validate_envelope(envelope),
         :ok <-
           check(
             valid["project_id"] == project and valid["snapshot_id"] == snapshot_id,
             :lookup_identity
           ) do
      {:ok, valid}
    end
  end

  defp storage_key(project, snapshot_id) do
    if nonempty?(project) and sha?(snapshot_id) do
      with {:ok, value} <- JSON.encode([project, snapshot_id]) do
        {:ok, digest(value)}
      end
    else
      {:error, :invalid_v2_snapshot_key}
    end
  end

  @doc "Lossless, typed v2 reference: direct evidence uses [its own ID]."
  def reference(envelope, kind, id) do
    with {:ok, snap} <- validate_envelope(envelope),
         {:ok, object} <- find_object(snap["upstream"], kind, id) do
      reference = %{
        "schema_version" => 2,
        "upstream_schema_version" => 2,
        "provider" => "beamcompass",
        "project_id" => snap["project_id"],
        "snapshot_id" => snap["snapshot_id"],
        "object_kind" => kind,
        "object_id" => id,
        "evidence_ids" => object_evidence(kind, object)
      }

      reference =
        if kind == "evidence" do
          reference
        else
          Map.put(reference, "epistemic_status", object["epistemic_status"])
        end

      reference =
        if kind == "relation" do
          Map.put(reference, "resolution", object["resolution"])
        else
          reference
        end

      Core.validate("behavior_ref_v2", reference)
    end
  end

  @doc "Exact project, snapshot, object kind, full evidence set and status checks."
  def resolve(envelope, reference) do
    with {:ok, snap} <- validate_envelope(envelope),
         {:ok, ref} <- Core.validate("behavior_ref_v2", reference),
         :ok <- exact_scope(snap, ref),
         {:ok, object} <- find_object(snap["upstream"], ref["object_kind"], ref["object_id"]),
         :ok <- exact_object(ref, object) do
      {:ok, object}
    end
  end

  defp exact_scope(snap, ref) do
    if ref["project_id"] == snap["project_id"] and ref["snapshot_id"] == snap["snapshot_id"] do
      :ok
    else
      {:error, {:reference_scope_mismatch, ref["object_id"]}}
    end
  end

  defp exact_object(ref, object) do
    kind = ref["object_kind"]

    if ref["evidence_ids"] == object_evidence(kind, object) and
         (not Map.has_key?(ref, "epistemic_status") or
            ref["epistemic_status"] == object["epistemic_status"]) and
         (not Map.has_key?(ref, "resolution") or ref["resolution"] == object["resolution"]) do
      :ok
    else
      {:error, {:reference_evidence_mismatch, ref["object_id"]}}
    end
  end

  defp find_object(s, kind, id) when kind in ~w(entity relation evidence) and is_binary(id) do
    collection = %{"entity" => "entities", "relation" => "relations", "evidence" => "evidence"}

    case Enum.find(s[collection[kind]], &(&1["id"] == id)) do
      nil -> {:error, {:unresolved_reference, kind, id}}
      object -> {:ok, object}
    end
  end

  defp find_object(_, _, _), do: {:error, :invalid_v2_object_kind_or_id}

  defp object_evidence("evidence", object), do: [object["id"]]
  defp object_evidence(_, object), do: object["evidence_ids"]

  defp keys?(map, fields) when is_map(map), do: Enum.sort(Map.keys(map)) == Enum.sort(fields)
  defp keys?(_, _), do: false
  defp nonempty?(value), do: is_binary(value) and byte_size(value) > 0
  defp sha?(value), do: is_binary(value) and Regex.match?(@sha, value)

  defp strings?(values, minimum \\ 0) do
    is_list(values) and length(values) >= minimum and length(values) <= @max_items and
      Enum.all?(values, &nonempty?/1) and Enum.sort(values) == values and
      Enum.uniq(values) == values
  end

  defp collection?(values, valid, minimum \\ 0) do
    is_list(values) and length(values) >= minimum and length(values) <= @max_items and
      Enum.all?(values, valid)
  end

  defp sorted_ids?(values) do
    ids = Enum.map(values, & &1["id"])
    Enum.sort(ids) == ids and Enum.uniq(ids) == ids
  end

  defp sorted_issues?(issues) do
    keys = Enum.map(issues, &{&1["code"], &1["message"], &1["evidence_ids"]})
    Enum.sort(keys) == keys and Enum.uniq(keys) == keys
  end

  defp subset?(ids, known), do: Enum.all?(ids, &MapSet.member?(known, &1))

  defp check(true, _), do: :ok
  defp check(_, reason), do: {:error, {:invalid_v2_snapshot, reason}}

  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
