defmodule Grand.Assurance.G05 do
  @moduledoc """
  Versioned G05 source-linked Lynx law and Veil model execution. Only exact,
  already-approved historical G03 obligation/revisions are accepted; neither
  this module nor its workers append to the G03 journal or unrun receipts.
  Historical G04 schema v1 and result v3 remain readable and unchanged.
  """

  alias Grand.Assurance.G03
  alias Grand.Assurance.G05.{Lynx, Veil}

  @adapters %{"lynx" => Lynx, "veil" => Veil}
  @statuses ~w(proved bounded_pass counterexample test_pass test_fail inconclusive unsupported error unrun stale)

  @spec run(binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(root, manifest, opts \\ [])

  def run(root, %{"schema_version" => 2, "adapter" => name} = manifest, opts)
      when is_binary(root) and is_list(opts) do
    with {:ok, adapter} <- adapter(name),
         :ok <- validate_manifest(manifest),
         {:ok, receipt} <- G03.receipt(root, manifest["obligation_id"]),
         :ok <- match_obligation(manifest, receipt),
         {:ok, plan} <- adapter.prepare(manifest, opts),
         {:ok, raw} <- adapter.execute(plan, opts),
         {:ok, verdict} <- adapter.normalize(plan, raw) do
      {:ok, result(manifest, receipt, plan, raw, verdict, opts)}
    end
  end

  def run(_, _, _), do: {:error, :invalid_g05_manifest}

  @doc "Compare a previous G05 v4 scoped result to exact current pins and staged files."
  @spec applicability(map(), binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def applicability(old, root, manifest, opts \\ [])

  def applicability(
        %{"format" => "grand.g05.scoped_result", "schema_version" => 4, "inputs" => inputs} = old,
        root,
        manifest,
        opts
      ) do
    with true <- old["status"] in @statuses and old["engine"] == manifest["adapter"],
         {:ok, adapter} <- adapter(manifest["adapter"]),
         {:ok, receipt} <- G03.receipt(root, manifest["obligation_id"]),
         :ok <- match_obligation(manifest, receipt),
         {:ok, plan} <- adapter.prepare(manifest, opts) do
      current = inputs(manifest, receipt, plan)

      requirement_reasons = requirement_changes(root, manifest, receipt)

      reasons =
        (~w(manifest requirement obligation assumption_revisions source_files tool)
         |> Enum.filter(&(Map.get(inputs, &1) != Map.get(current, &1)))) ++
          requirement_reasons

      reasons = Enum.uniq(reasons)

      if reasons == [] do
        {:ok, %{"applicability" => "current", "reasons" => []}}
      else
        {:ok,
         %{
           "applicability" => "stale",
           "reasons" => reasons,
           "prior_status" => old["status"],
           "effective_status" => "stale"
         }}
      end
    else
      false ->
        {:error, :invalid_g05_result}

      {:error, reason}
      when reason in [
             :g05_requirement_revision_mismatch,
             :g05_source_scope_mismatch,
             :g05_assumption_revision_mismatch,
             :g05_obligation_mismatch,
             :g05_requirement_not_approved,
             :missing_g05_binding
           ] ->
        {:ok,
         %{
           "applicability" => "stale",
           "reasons" => ["binding_rejected", Atom.to_string(reason)],
           "prior_status" => old["status"],
           "effective_status" => "stale"
         }}

      error ->
        error
    end
  end

  def applicability(_, _, _, _), do: {:error, :invalid_g05_result}

  defp adapter(name) do
    case Map.fetch(@adapters, name) do
      {:ok, adapter} -> {:ok, adapter}
      :error -> {:error, {:unsupported_g05_adapter, name}}
    end
  end

  defp requirement_changes(root, manifest, receipt) do
    expected = receipt["requirement"]

    case G03.latest(root, "requirement", manifest["requirement"]["id"]) do
      {:ok, ^expected} -> []
      _ -> ["requirement"]
    end
  end

  defp validate_manifest(manifest) do
    package = if manifest["adapter"] == "lynx", do: "law", else: "model"

    keys =
      ~w(schema_version adapter obligation_id requirement scope source_refs assumptions) ++
        [package]

    if Enum.sort(Map.keys(manifest)) == Enum.sort(keys),
      do: :ok,
      else: {:error, :invalid_g05_manifest}
  end

  defp match_obligation(manifest, receipt) do
    obligation = receipt["obligation"]
    required = ~w(schema_version adapter obligation_id requirement scope source_refs assumptions)

    cond do
      Enum.any?(required, &(not Map.has_key?(manifest, &1))) ->
        {:error, :missing_g05_binding}

      receipt["requirement"]["status"] != "approved" ->
        {:error, :g05_requirement_not_approved}

      manifest["obligation_id"] != obligation["id"] ->
        {:error, :g05_obligation_mismatch}

      not requirement_matches?(manifest, receipt) ->
        {:error, :g05_requirement_revision_mismatch}

      manifest["scope"] != obligation["scope"] or
          manifest["source_refs"] != obligation["source_refs"] ->
        {:error, :g05_source_scope_mismatch}

      manifest["assumptions"] != obligation["assumptions"] ->
        {:error, :g05_assumption_revision_mismatch}

      true ->
        :ok
    end
  end

  defp requirement_matches?(manifest, receipt) do
    manifest["requirement"] == receipt["obligation"]["requirement"] and
      manifest["requirement"] == Map.take(receipt["requirement"], ["id", "revision"])
  end

  defp inputs(manifest, receipt, plan) do
    %{
      "manifest" => manifest,
      "requirement" => receipt["requirement"],
      "obligation" => receipt["obligation"],
      "assumption_revisions" => receipt["assumption_revisions"],
      "source_files" => plan["source_files"],
      "tool" => plan["tool"]
    }
  end

  defp result(manifest, receipt, plan, raw, verdict, opts) do
    %{
      "format" => "grand.g05.scoped_result",
      "schema_version" => 4,
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
      "inputs" => inputs(manifest, receipt, plan),
      "runner" => %{
        "execution_requested" => Keyword.get(opts, :execute, false),
        "law_code_authorized" => Keyword.get(opts, :allow_law_code, false),
        "timeout_ms" => Keyword.get(opts, :timeout_ms, 5_000),
        "output_limit_bytes" => Keyword.get(opts, :output_limit_bytes, 65_536),
        "exit_code" => raw["exit_code"],
        "elapsed_ms" => raw["elapsed_ms"],
        "reason" => raw["reason"]
      },
      "diagnostics" => verdict["diagnostics"],
      "counterexample" => verdict["counterexample"],
      "theorems" => verdict["theorems"],
      "dependencies" => verdict["dependencies"],
      "axioms" => verdict["axioms"],
      "stdout" => raw["stdout"],
      "stderr" => raw["stderr"],
      "guarantee" => "only_named_translated_law_or_finite_model_under_disclosed_assumptions",
      "identity_assurance" => "manual_self_attestation_not_authenticated"
    }
  end
end
