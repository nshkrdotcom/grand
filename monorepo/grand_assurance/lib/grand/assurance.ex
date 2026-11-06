defmodule Grand.Assurance do
  @moduledoc """
  Grand-owned human requirement lifecycle and deliberately unrun G01A receipts.

  Approval uses explicit, human-labeled CLI attestations but is NOT identity
  authentication. No evidence or verification verdict is inferred from approval.
  """

  alias Grand.Core
  alias Grand.Core.JSON
  alias Grand.Core.Store

  @unrun_notice "No model checker, tests of target code, or proof engine were run"

  @doc "Attach a manually provided pending requirement to an exact, resolved fact."
  def link_requirement(requirement, reference, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    at = Keyword.get(opts, :at, now())

    with {:ok, req} <- Core.validate("requirement", requirement),
         {:ok, ref} <- Core.validate("behavior_ref", reference),
         true <- req["status"] == "pending_approval" and req["revision"] == 1,
         true <- Map.get(req, "behavior_refs", []) == [],
         true <- req["approval_events"] == [],
         :ok <- human_actor(actor),
         :ok <- timestamp(at) do
      linked =
        req
        |> Map.put("behavior_refs", [ref])
        |> Map.put("approval_events", [%{
          "actor" => actor,
          "action" => "submit",
          "at" => at,
          "revision" => req["revision"]
        }])

      Core.validate("requirement", linked)
    else
      false -> {:error, :requirement_must_be_new_unlinked_pending_revision_one}
      error -> error
    end
  end

  @doc "Manual attestation, creating a new immutable revision. NOT cryptographic authentication."
  def approve(requirement, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    at = Keyword.get(opts, :at, now())
    acknowledgement = Keyword.get(opts, :ack_human, false)

    with {:ok, req} <- Core.validate("requirement", requirement),
         true <- acknowledgement == true,
         :ok <- human_actor(actor),
         :ok <- timestamp(at),
         true <- req["status"] == "pending_approval", 
         true <- Map.get(req, "behavior_refs", []) != [],
         true <- Enum.any?(req["approval_events"], &(&1["action"] == "submit")) do
      revision = req["revision"] + 1

      approved =
        req
        |> Map.put("revision", revision)
        |> Map.put("status", "approved")
        |> Map.update!("approval_events", fn events ->
          events ++ [%{"actor" => actor, "action" => "approve", "at" => at, "revision" => revision}]
        end)

      Core.validate("requirement", approved)
    else
      false -> {:error, :approval_requires_pending_link_and_explicit_human_acknowledgement}
      error -> error
    end
  end

  defp human_actor(actor) do
    cond do
      not Core.nonempty?(actor) -> {:error, :human_actor_required}
      not String.starts_with?(actor, "human:") -> {:error, :human_identity_label_required}
      byte_size(actor) > 160 -> {:error, :actor_label_too_long}
      String.trim(String.replace_prefix(actor, "human:", "")) == "" -> {:error, :human_actor_required}
      true -> :ok
    end
  end

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _, _} -> :ok
      _ -> {:error, :invalid_iso8601_timestamp}
    end
  end

  defp timestamp(_), do: {:error, :invalid_iso8601_timestamp}
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  def save_requirement(root, req) do
    with {:ok, record} <- Core.validate("requirement", req) do
      Store.put(root, "requirements", "#{record["id"]}@#{record["revision"]}", record)
    end
  end

  def latest(root, id), do: Store.latest_requirement(root, id)

  @doc "Build a portable bundle whose obligation and VerificationRun say unrun."
  def unrun_bundle(requirement, reference, source_digest) do
    with {:ok, req} <- Core.validate("requirement", requirement),
         {:ok, ref} <- Core.validate("behavior_ref", reference),
         true <- Core.nonempty?(source_digest),
         true <- ref in Map.get(req, "behavior_refs", []),
         true <- req["approval_events"] != [],
         {:ok, fingerprint_data} <- fingerprint_payload(req, ref, source_digest),
         {:ok, normalized} <- JSON.encode(fingerprint_data) do
      hash = digest(normalized)
      obligation_id = "g01a-unformalized-" <> String.slice(hash, 0, 24)
      run_id = "g01a-unrun-" <> String.slice(hash, 0, 24)
      at = req["approval_events"] |> List.last() |> Map.fetch!("at")

      obligation = %{
        "schema_version" => 1,
        "id" => obligation_id,
        "requirement_id" => req["id"],
        "requirement_revision" => req["revision"],
        "property" => "UNFORMALIZED manual requirement: " <> req["statement"],
        "kind" => "other",
        "assumption_ids" => Map.get(req, "assumption_ids", []),
        "source_refs" => [ref],
        "preconditions" => ["No formal model or checker selected"]
      }

      run = %{
        "schema_version" => 1,
        "run_id" => run_id,
        "obligation_id" => obligation_id,
        "status" => "unrun",
        "input_fingerprint" => "sha256:" <> hash,
        "engine" => "none-not-invoked",
        "scope" => %{
          "execution" => "not_attempted",
          "evidence_level" => "syntactic_source_only",
          "snapshot_id" => ref["snapshot_id"],
          "requirement_approval" => req["status"]
        },
        "recorded_at" => at,
        "diagnostics" => [@unrun_notice],
        "assumption_ids" => Map.get(req, "assumption_ids", [])
      }

      record = %{
        "schema_version" => 1,
        "id" => "g01a-receipt-" <> String.slice(hash, 0, 24),
        "requirement_id" => req["id"],
        "requirement_revision" => req["revision"],
        "behavior_refs" => [ref],
        "obligation_ids" => [obligation_id],
        "run_ids" => [run_id],
        "assumption_ids" => Map.get(req, "assumption_ids", []),
        "coverage_summary" => %{
          "status" => "unassessed",
          "limitations" => [@unrun_notice, "Human approval is not a verification result"]
        },
        "created_at" => at
      }

      with {:ok, _} <- Core.validate("obligation", obligation),
           {:ok, _} <- Core.validate("verification_result", run),
           {:ok, _} <- Core.validate("assurance_record", record) do
        {:ok,
         %{
           "format" => "grand.g01a.assurance_bundle",
           "schema_version" => 1,
           "requirement" => req,
           "behavior_ref" => ref,
           "source_digest" => source_digest,
           "obligation" => obligation,
           "verification_result" => run,
           "assurance_record" => record
         }}
      end
    else
      false -> {:error, :unresolved_or_unapproved_requirement_reference}
      error -> error
    end
  end

  defp fingerprint_payload(req, ref, source_digest) do
    {:ok,
     %{
       "kind" => "grand.g01a.not_attempted",
       "requirement_id" => req["id"],
       "requirement_revision" => req["revision"],
       "statement" => req["statement"],
       "requirement_status" => req["status"],
       "behavior_ref" => ref,
       "snapshot_source_sha256" => source_digest,
       "runner_policy" => "no_checker_run",
       "assumption_ids" => Map.get(req, "assumption_ids", [])
     }}
  end

  defp digest(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
