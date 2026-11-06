defmodule Grand.BeamCompass do
  @moduledoc """
  Read-only, version-checked BeamCompass portable JSON v1 adapter.

  This is not a BeamCompass implementation dependency. No target Mix project,
  source file, command or callback is evaluated. A v1 fact is only a syntactic
  observation, and capsules remain function-local/provisional.
  """

  alias Grand.Core
  alias Grand.Core.JSON
  alias Grand.Core.Store

  @max_bytes 4_000_000
  @fact_status ~w(source proposed unresolved)
  @limited "BeamCompass v1 syntactic fact only; not observed runtime or causal closure"

  @spec import_file(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def import_file(path, opts) when is_binary(path) and is_list(opts) do
    project_id = Keyword.get(opts, :project_id)

    with true <- Core.valid_id?(project_id),
         {:ok, %{size: size}} <- File.stat(path),
         true <- size <= @max_bytes,
         {:ok, source} <- File.read(path),
         {:ok, upstream} <- JSON.decode(source, max_bytes: @max_bytes),
         {:ok, validated} <- validate_v1(upstream),
         {:ok, canonical} <- JSON.encode(validated) do
      {:ok,
       %{
         "schema_version" => 1,
         "format" => "grand.beamcompass.v1.import",
         "project_id" => project_id,
         "snapshot_id" => validated["id"],
         "source_sha256" => digest(source),
         "canonical_sha256" => digest(canonical),
         "upstream" => validated,
         "capsule_assessments" =>
           Enum.with_index(validated["capsules"])
           |> Enum.map(fn {_capsule, index} ->
             %{
               "index" => index,
               "confidence" => "provisional",
               "limitations" => [
                 "Function-local v1 capsule; no transitive process or effect claim"
               ]
             }
           end)
       }}
    else
      false when is_nil(project_id) -> {:error, :project_id_required}
      false -> {:error, :invalid_project_or_oversized_input}
      {:error, _} = error -> error
    end
  end

  def import_file(_, _), do: {:error, :invalid_import_arguments}

  @spec validate_v1(term()) :: {:ok, map()} | {:error, term()}
  def validate_v1(snapshot) when is_map(snapshot) do
    version = Map.get(snapshot, "schema_version")

    cond do
      version == nil -> {:error, {:invalid_snapshot, :missing_schema_version}}
      version != 1 -> {:error, {:unsupported_schema_version, version}}
      true -> validate_v1_fields(snapshot)
    end
  end

  def validate_v1(_), do: {:error, {:invalid_snapshot, :expected_object}}

  defp validate_v1_fields(snapshot) do
    expected = ~w(schema_version id projects facts capsules issues)

    cond do
      Enum.sort(Map.keys(snapshot)) != Enum.sort(expected) ->
        {:error, {:invalid_snapshot, :invalid_top_level_fields}}

      not Core.valid_id?(snapshot["id"]) ->
        {:error, {:invalid_snapshot, :invalid_snapshot_id}}

      not list_of_objects?(snapshot["projects"], 1_000) ->
        {:error, {:invalid_snapshot, :invalid_projects}}

      not list_of_objects?(snapshot["capsules"], 10_000) ->
        {:error, {:invalid_snapshot, :invalid_capsules}}

      not list_of_objects?(snapshot["issues"], 10_000) ->
        {:error, {:invalid_snapshot, :invalid_issues}}

      not bounded_facts?(snapshot["facts"]) ->
        {:error, {:invalid_snapshot, :invalid_facts}}

      not Enum.all?(snapshot["facts"], &valid_fact?/1) ->
        {:error, {:invalid_snapshot, :invalid_fact_or_anchor}}

      true ->
        validate_unique_facts(snapshot)
    end
  end

  defp validate_unique_facts(snapshot) do
    ids = Enum.map(snapshot["facts"], & &1["id"])

    if length(ids) == length(Enum.uniq(ids)),
      do: {:ok, snapshot},
      else: {:error, {:invalid_snapshot, :duplicate_fact_id}}
  end

  defp bounded_facts?(facts), do: is_list(facts) and length(facts) <= 10_000

  defp list_of_objects?(value, max) do
    is_list(value) and length(value) <= max and Enum.all?(value, &is_map/1)
  end

  defp valid_fact?(fact) when is_map(fact) do
    fields = ~w(id kind subject object status anchor details)
    anchor = Map.get(fact, "anchor")

    Enum.all?(fields, &Map.has_key?(fact, &1)) and
      Core.valid_id?(fact["id"]) and
      Core.nonempty?(fact["kind"]) and
      is_binary(fact["subject"]) and
      is_binary(fact["object"]) and
      fact["status"] in @fact_status and
      is_map(fact["details"]) and
      valid_anchor?(anchor)
  end

  defp valid_fact?(_), do: false

  defp valid_anchor?(anchor) when is_map(anchor) do
    valid_relative_path?(anchor["path"]) and
      Core.positive?(anchor["line"]) and
      Core.positive?(anchor["column"])
  end

  defp valid_anchor?(_), do: false

  @doc "No filesystem accesses; verifies a portable path has no traversal/drive prefix."
  def valid_relative_path?(value) when is_binary(value) do
    parts = String.split(value, "/")

    value != "" and String.valid?(value) and not String.starts_with?(value, "/") and
      not String.contains?(value, ["\\", <<0>>]) and
      not Regex.match?(~r/\A[A-Za-z]:/, value) and
      Enum.all?(parts, fn p -> p != "" and p != "." and p != ".." end)
  end

  def valid_relative_path?(_), do: false

  @spec reference(map(), binary()) :: {:ok, map()} | {:error, term()}
  def reference(snapshot, fact_id) do
    with {:ok, snap} <- validate_envelope(snapshot),
         true <- Core.valid_id?(fact_id),
         {:ok, fact} <- find_fact(snap, fact_id) do
      ref = %{
        "schema_version" => 1,
        "provider" => "beamcompass",
        "project_id" => snap["project_id"],
        "snapshot_id" => snap["snapshot_id"],
        "upstream_schema_version" => 1,
        "object_kind" => "fact",
        "object_id" => fact["id"],
        "evidence_ids" => [fact["id"]],
        "epistemic_status" => fact["status"],
        "limitations" => [@limited]
      }

      Core.validate("behavior_ref", ref)
    else
      false -> {:error, {:unresolved_reference, fact_id}}
      error -> error
    end
  end

  @spec resolve(map(), map()) :: {:ok, map()} | {:error, term()}
  def resolve(snapshot, reference) do
    with {:ok, snap} <- validate_envelope(snapshot),
         {:ok, ref} <- Core.validate("behavior_ref", reference),
         :ok <- exact_scope(snap, ref),
         {:ok, fact} <- find_fact(snap, ref["object_id"]),
         :ok <- exact_fact(fact, ref) do
      {:ok, fact}
    end
  end

  defp exact_scope(snapshot, ref) do
    if ref["project_id"] == snapshot["project_id"] and
         ref["snapshot_id"] == snapshot["snapshot_id"] and
         ref["upstream_schema_version"] == 1 and ref["object_kind"] == "fact" do
      :ok
    else
      {:error, {:reference_scope_mismatch, ref["object_id"]}}
    end
  end

  defp exact_fact(fact, ref) do
    if ref["evidence_ids"] == [fact["id"]] and
         (not Map.has_key?(ref, "epistemic_status") or
            ref["epistemic_status"] == fact["status"]) do
      :ok
    else
      {:error, {:reference_evidence_mismatch, fact["id"]}}
    end
  end

  defp find_fact(snapshot, fact_id) do
    case Enum.find(snapshot["upstream"]["facts"], &(&1["id"] == fact_id)) do
      nil -> {:error, {:unresolved_reference, fact_id}}
      fact -> {:ok, fact}
    end
  end

  @doc "Load-only validation of persisted snapshot, including canonical hash."
  def validate_envelope(envelope) when is_map(envelope) do
    with true <- envelope["format"] == "grand.beamcompass.v1.import",
         true <- envelope["schema_version"] == 1,
         true <- Core.valid_id?(envelope["project_id"]),
         true <- Core.valid_id?(envelope["snapshot_id"]),
         {:ok, snapshot} <- validate_v1(envelope["upstream"]),
         true <- snapshot["id"] == envelope["snapshot_id"],
         {:ok, canonical} <- JSON.encode(snapshot),
         true <- digest(canonical) == envelope["canonical_sha256"] do
      {:ok, envelope}
    else
      _ -> {:error, {:invalid_snapshot, :stored_envelope_invalid_or_modified}}
    end
  end

  def validate_envelope(_), do: {:error, {:invalid_snapshot, :expected_envelope}}

  @spec store(map(), binary()) :: {:ok, binary()} | {:error, term()}
  def store(snapshot, root) do
    with {:ok, envelope} <- validate_envelope(snapshot) do
      Store.put(
        root,
        "snapshots",
        snapshot_key(envelope["project_id"], envelope["snapshot_id"]),
        envelope
      )
    end
  end

  @spec load(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def load(root, project_id, snapshot_id) do
    with true <- Core.valid_id?(project_id) and Core.valid_id?(snapshot_id),
         {:ok, envelope} <- Store.get(root, "snapshots", snapshot_key(project_id, snapshot_id)),
         {:ok, valid} <- validate_envelope(envelope),
         true <- valid["project_id"] == project_id and valid["snapshot_id"] == snapshot_id do
      {:ok, valid}
    else
      false -> {:error, :invalid_snapshot_key}
      error -> error
    end
  end

  def snapshot_key(project_id, snapshot_id), do: "#{project_id}::#{snapshot_id}"
  defp digest(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
