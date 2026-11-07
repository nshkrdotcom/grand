defmodule Grand.Assurance.G04 do
  @moduledoc """
  Optional, scoped G04 checks against an existing G03 obligation. No implicit
  execution and no changes to the G03 journal or its historical unrun receipt.

  `run/3` accepts a *data* manifest. An explicitly opted-in external engine is
  the only component that can check a law/model. Result statuses are never a
  single verified boolean; a model pass is never an unbounded proof.
  """

  alias Grand.Assurance.G03
  alias Grand.Assurance.G04.Lean
  alias Grand.Assurance.G04.TLC

  @adapters %{"lean" => Lean, "tlc" => TLC}

  @doc "Inspect or explicitly run a verification manifest for an existing G03 obligation."
  @spec run(binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(root, manifest, opts \\ [])

  def run(root, %{"schema_version" => 1, "adapter" => adapter_name} = manifest, opts)
      when is_binary(root) and is_list(opts) do
    with {:ok, adapter} <- adapter(adapter_name),
         {:ok, receipt} <- G03.receipt(root, manifest["obligation_id"]),
         :ok <- match_obligation(manifest, receipt),
         {:ok, prepared} <- adapter.prepare(manifest, opts),
         {:ok, raw} <- adapter.execute(prepared, opts),
         {:ok, verdict} <- adapter.normalize(prepared, raw) do
      {:ok, result(manifest, receipt, prepared, raw, verdict, opts)}
    end
  end

  def run(_, _, _), do: {:error, :invalid_g04_manifest}

  @doc "Check whether an earlier result still describes exactly these inputs."
  @spec applicability(map(), binary(), map()) :: {:ok, binary()} | {:error, term()}
  def applicability(%{"inputs" => inputs}, root, manifest) do
    with {:ok, receipt} <- G03.receipt(root, manifest["obligation_id"]),
         :ok <- match_obligation(manifest, receipt),
         {:ok, adapter} <- adapter(manifest["adapter"]),
         {:ok, prepared} <- adapter.prepare(manifest, []) do
      comparison = %{
        "manifest" => manifest,
        "requirement" => receipt["requirement"],
        "obligation" => receipt["obligation"],
        "assumption_revisions" => receipt["assumption_revisions"],
        "source_files" => prepared["source_files"]
      }

      if inputs == comparison, do: {:ok, "current"}, else: {:ok, "stale"}
    end
  end

  def applicability(_, _, _), do: {:error, :invalid_g04_result}

  defp adapter(name) do
    case Map.fetch(@adapters, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unsupported_g04_adapter, name}}
    end
  end

  defp match_obligation(m, r) do
    required = ~w(schema_version adapter obligation_id requirement scope source_refs assumptions)
    actual = r["obligation"]

    cond do
      Enum.any?(required, &(not Map.has_key?(m, &1))) ->
        {:error, :missing_g04_binding}

      r["requirement"]["status"] != "approved" ->
        {:error, :g04_requirement_not_approved}

      m["obligation_id"] != actual["id"] ->
        {:error, :g04_obligation_mismatch}

      not same_requirement?(m, actual, r) ->
        {:error, :g04_requirement_revision_mismatch}

      m["scope"] != actual["scope"] or m["source_refs"] != actual["source_refs"] ->
        {:error, :g04_source_scope_mismatch}

      m["assumptions"] != actual["assumptions"] ->
        {:error, :g04_assumption_revision_mismatch}

      true ->
        :ok
    end
  end

  defp same_requirement?(manifest, obligation, receipt) do
    manifest["requirement"] == obligation["requirement"] and
      manifest["requirement"] == Map.take(receipt["requirement"], ["id", "revision"])
  end

  defp result(manifest, receipt, plan, raw, verdict, opts) do
    %{
      "format" => "grand.g04.scoped_result",
      "schema_version" => 3,
      "obligation_id" => manifest["obligation_id"],
      "status" => verdict["status"],
      "engine" => manifest["adapter"],
      "engine_version" => verdict["engine_version"],
      "property" => plan["property"],
      "scope" => manifest["scope"],
      "qualifications" => plan["qualifications"],
      "open_gaps" => receipt["open_gaps"],
      "witness_challenge" => receipt["witness_challenge"],
      "assumption_revisions" => receipt["assumption_revisions"],
      "inputs" => %{
        "manifest" => manifest,
        "requirement" => receipt["requirement"],
        "obligation" => receipt["obligation"],
        "assumption_revisions" => receipt["assumption_revisions"],
        "source_files" => plan["source_files"]
      },
      "runner" => %{
        "execution_requested" => Keyword.get(opts, :execute, false),
        "timeout_ms" => Keyword.get(opts, :timeout_ms, 5_000),
        "output_limit_bytes" => Keyword.get(opts, :output_limit_bytes, 65_536),
        "exit_code" => raw["exit_code"],
        "elapsed_ms" => raw["elapsed_ms"],
        "reason" => raw["reason"]
      },
      "diagnostics" => verdict["diagnostics"],
      "counterexample" => verdict["counterexample"],
      "stdout" => raw["stdout"],
      "stderr" => raw["stderr"],
      "guarantee" => "only_the_named_law_or_finite_model_under_stated_assumptions",
      "identity_assurance" => "manual_self_attestation_not_authenticated"
    }
  end
end
