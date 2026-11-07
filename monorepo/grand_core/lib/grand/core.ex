defmodule Grand.Core do
  @moduledoc """
  Grand-owned portable record validation and deterministic JSON encoding.

  This v1 validator enforces the fields used in the authoritative Grand schemas.
  Cross-record reference resolution remains an application-level responsibility.
  No untrusted input is converted into an atom.
  """

  alias Grand.Core.G03
  alias Grand.Core.JSON

  @id ~r/\A[A-Za-z0-9][A-Za-z0-9._:\/-]*\z/
  @fact_kinds ~w(fact entity relationship behavior capsule transition effect effect_intent state_holder channel)
  @epistemic ~w(source derived observed proposed unresolved)
  @requirements ~w(draft pending_approval approved superseded rejected)
  @runs ~w(proved bounded_pass counterexample test_pass test_fail inconclusive unsupported error unrun stale)
  @coverage ~w(unassessed partial scoped_evidence unresolved stale)
  @obligation_kinds ~w(lynx lean veil tlc quint exunit property conformance other)

  @spec encode(term()) :: {:ok, binary()} | {:error, term()}
  def encode(value), do: JSON.encode(value)

  @spec decode(binary(), String.t()) :: {:ok, map()} | {:error, term()}
  def decode(binary, schema) do
    with {:ok, data} <- JSON.decode(binary), do: validate(schema, data)
  end

  @spec validate(String.t(), term()) :: {:ok, map()} | {:error, term()}
  def validate("candidate_v2", data), do: G03.validate("candidate", data)
  def validate("requirement_v2", data), do: G03.validate("requirement", data)
  def validate("assumption_v2", data), do: G03.validate("assumption", data)
  def validate("obligation_v2", data), do: G03.validate("obligation", data)

  def validate(schema, data) when is_map(data) and is_binary(schema) do
    case fields(schema) do
      {:ok, required, optional} ->
        errors =
          missing_fields(data, required) ++
            unexpected_fields(data, required ++ optional) ++ field_errors(schema, data)

        if errors == [],
          do: {:ok, data},
          else: {:error, {:invalid_record, schema, Enum.sort(errors)}}

      :unknown ->
        {:error, {:unsupported_record_schema, schema}}
    end
  end

  def validate(schema, _), do: {:error, {:invalid_record, schema, ["expected object"]}}

  defp missing_fields(data, required) do
    Enum.flat_map(required, fn key ->
      if Map.has_key?(data, key), do: [], else: ["missing #{key}"]
    end)
  end

  defp unexpected_fields(data, allowed) do
    Enum.flat_map(Map.keys(data), fn key ->
      if key in allowed, do: [], else: ["unexpected #{inspect(key)}"]
    end)
  end

  def valid_id?(value), do: is_binary(value) and Regex.match?(@id, value)
  def nonempty?(value), do: is_binary(value) and String.trim(value) != ""
  def positive?(value), do: is_integer(value) and value > 0
  def text_list?(value), do: is_list(value) and Enum.all?(value, &nonempty?/1) and unique?(value)
  def ids?(value), do: is_list(value) and Enum.all?(value, &valid_id?/1) and unique?(value)

  defp unique?(list), do: length(list) == length(Enum.uniq(list))
  defp one_of?(value, candidates), do: is_binary(value) and value in candidates
  defp object?(value), do: is_map(value)
  defp references?(value), do: is_list(value) and Enum.all?(value, &valid_ref?/1)
  defp valid_ref?(v), do: match?({:ok, _}, validate("behavior_ref", v))

  defp optional_field(data, field, check),
    do: not Map.has_key?(data, field) or check.(Map.get(data, field))

  defp fields("behavior_ref") do
    {:ok,
     ~w(schema_version provider project_id snapshot_id upstream_schema_version object_kind object_id evidence_ids),
     ~w(epistemic_status limitations)}
  end

  defp fields("behavior_ref_v2") do
    {:ok,
     ~w(schema_version provider project_id snapshot_id upstream_schema_version object_kind object_id evidence_ids),
     ~w(epistemic_status resolution)}
  end

  defp fields("requirement") do
    {:ok, ~w(schema_version id revision statement status owner approval_events),
     ~w(scope behavior_refs assumption_ids supersedes_id)}
  end

  defp fields("assurance_record") do
    {:ok,
     ~w(schema_version id requirement_id requirement_revision behavior_refs obligation_ids run_ids assumption_ids coverage_summary created_at),
     ~w(approval_event_refs)}
  end

  defp fields("verification_result") do
    {:ok,
     ~w(schema_version run_id obligation_id status input_fingerprint engine scope recorded_at),
     ~w(engine_version source_hash model_hash artifact_hashes assumption_ids diagnostics elapsed_ms)}
  end

  defp fields("obligation") do
    {:ok, ~w(schema_version id requirement_id requirement_revision property kind assumption_ids),
     ~w(source_refs model_hash preconditions)}
  end

  defp fields(_), do: :unknown

  defp field_errors(schema, data) do
    specs =
      case schema do
        "behavior_ref" -> ref_fields()
        "behavior_ref_v2" -> ref_v2_fields()
        "requirement" -> requirement_fields()
        "assurance_record" -> assurance_fields()
        "verification_result" -> verification_fields()
        "obligation" -> obligation_fields()
      end

    errors =
      Enum.flat_map(specs, fn {key, validator} ->
        if optional_field(data, key, validator), do: [], else: ["invalid #{key}"]
      end)

    errors ++ semantic_errors(schema, data)
  end

  defp common_version, do: [{"schema_version", &(&1 == 1)}]

  defp ref_fields do
    common_version() ++
      [
        {"provider", &(&1 == "beamcompass")},
        {"project_id", &valid_id?/1},
        {"snapshot_id", &valid_id?/1},
        {"upstream_schema_version", &positive?/1},
        {"object_kind", &one_of?(&1, @fact_kinds)},
        {"object_id", &valid_id?/1},
        {"evidence_ids", &ids?/1},
        {"epistemic_status", &one_of?(&1, @epistemic)},
        {"limitations", &text_list?/1}
      ]
  end

  defp ref_v2_fields do
    [
      {"schema_version", &(&1 == 2)},
      {"provider", &(&1 == "beamcompass")},
      {"project_id", &v2_text?/1},
      {"snapshot_id", &(is_binary(&1) and Regex.match?(~r/\A[0-9a-f]{64}\z/, &1))},
      {"upstream_schema_version", &(&1 == 2)},
      {"object_kind", &one_of?(&1, ~w(entity relation evidence))},
      {"object_id", &v2_text?/1},
      {"evidence_ids", &v2_evidence_ids?/1},
      {"epistemic_status", &one_of?(&1, ~w(sourced derived proposed unresolved))},
      {"resolution", &one_of?(&1, ~w(resolved possible unresolved))}
    ]
  end

  defp v2_text?(value), do: is_binary(value) and byte_size(value) > 0

  defp v2_evidence_ids?(values) do
    is_list(values) and values != [] and Enum.all?(values, &v2_text?/1) and
      values == Enum.sort(values) and values == Enum.uniq(values)
  end

  defp requirement_fields do
    common_version() ++
      [
        {"id", &valid_id?/1},
        {"revision", &positive?/1},
        {"statement", &nonempty?/1},
        {"status", &one_of?(&1, @requirements)},
        {"owner", &nonempty?/1},
        {"scope", &nonempty?/1},
        {"behavior_refs", &references?/1},
        {"assumption_ids", &ids?/1},
        {"supersedes_id", &valid_id?/1},
        {"approval_events",
         fn events -> is_list(events) and Enum.all?(events, &valid_event?/1) end}
      ]
  end

  defp assurance_fields do
    common_version() ++
      [
        {"id", &valid_id?/1},
        {"requirement_id", &valid_id?/1},
        {"requirement_revision", &positive?/1},
        {"behavior_refs", &references?/1},
        {"obligation_ids", &ids?/1},
        {"run_ids", &ids?/1},
        {"assumption_ids", &ids?/1},
        {"created_at", &nonempty?/1},
        {"approval_event_refs", &ids?/1},
        {"coverage_summary",
         fn summary ->
           is_map(summary) and
             Enum.sort(Map.keys(summary)) == ~w(limitations status) and
             one_of?(Map.get(summary, "status"), @coverage) and
             text_list?(Map.get(summary, "limitations"))
         end}
      ]
  end

  defp verification_fields do
    common_version() ++
      [
        {"run_id", &valid_id?/1},
        {"obligation_id", &valid_id?/1},
        {"status", &one_of?(&1, @runs)},
        {"input_fingerprint", &nonempty?/1},
        {"engine", &nonempty?/1},
        {"engine_version", &nonempty?/1},
        {"source_hash", &nonempty?/1},
        {"model_hash", &nonempty?/1},
        {"scope", &object?/1},
        {"recorded_at", &nonempty?/1},
        {"artifact_hashes", &ids?/1},
        {"assumption_ids", &ids?/1},
        {"diagnostics", &text_list?/1},
        {"elapsed_ms", &(is_integer(&1) and &1 >= 0)}
      ]
  end

  defp obligation_fields do
    common_version() ++
      [
        {"id", &valid_id?/1},
        {"requirement_id", &valid_id?/1},
        {"requirement_revision", &positive?/1},
        {"property", &nonempty?/1},
        {"kind", &one_of?(&1, @obligation_kinds)},
        {"assumption_ids", &ids?/1},
        {"source_refs", &references?/1},
        {"model_hash", &nonempty?/1},
        {"preconditions", &text_list?/1}
      ]
  end

  defp valid_event?(event) when is_map(event) do
    Enum.sort(Map.keys(event)) == ~w(action actor at revision) and
      nonempty?(Map.get(event, "actor")) and
      one_of?(Map.get(event, "action"), ~w(submit approve reject supersede)) and
      nonempty?(Map.get(event, "at")) and positive?(Map.get(event, "revision"))
  end

  defp valid_event?(_), do: false

  defp semantic_errors("behavior_ref_v2", data) do
    case data["object_kind"] do
      "evidence" ->
        if Map.has_key?(data, "epistemic_status") or Map.has_key?(data, "resolution"),
          do: ["evidence ref cannot assert entity epistemic status or relation resolution"],
          else: []

      "entity" ->
        if Map.has_key?(data, "resolution"),
          do: ["entity ref cannot assert relation resolution"],
          else: []

      _ ->
        []
    end
  end

  defp semantic_errors("requirement", data) do
    events = Map.get(data, "approval_events", [])

    cond do
      not is_list(events) ->
        []

      Map.get(data, "status") != "approved" ->
        []

      Enum.any?(events, fn event ->
        is_map(event) and Map.get(event, "action") == "approve" and
            Map.get(event, "revision") == Map.get(data, "revision")
      end) ->
        []

      true ->
        ["approved requirement needs same-revision approval event"]
    end
  end

  defp semantic_errors(_, _), do: []
end
