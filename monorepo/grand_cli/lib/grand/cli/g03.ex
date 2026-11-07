defmodule Grand.CLI.G03 do
  @moduledoc """
  Explicit G03 v2 CLI; legacy commands remain untouched. Reads only supplied
  bounded JSON and imported immutable snapshots. Never runs target code.
  """

  alias Grand.Assurance.G03, as: Lifecycle
  alias Grand.BeamCompass
  alias Grand.BeamCompass.Motif
  alias Grand.Core.JSON

  @max_bytes 4_000_000
  @input_fields %{
    "candidate" => ~w(id question rationale counterhypothesis uncertainty gaps scope source_refs context),
    "requirement" => ~w(id statement owner scope behavior_refs assumptions source_candidate_id),
    "assumption" => ~w(id statement category owner scope evidence gaps),
    "obligation" => ~w(id requirement property kind scope source_refs assumptions preconditions witness precondition_challenges open_gaps)
  }
  @types ~w(candidate requirement assumption obligation)

  @doc "Run an explicit lifecycle subcommand with the already parsed CLI switches."
  def run(["propose", file], opts), do: create("candidate", file, opts)
  def run(["requirement", "draft", file], opts), do: create("requirement", file, opts)
  def run(["assumption", "register", file], opts), do: create("assumption", file, opts)
  def run(["obligation", "create", file], opts), do: create("obligation", file, opts)

  def run(["candidate", action, id], opts) when action in ~w(reject supersede) do
    with {:ok, root} <- required(opts, :store),
         {:ok, actor_opts} <- review_options(opts) do
      Lifecycle.decide_candidate(root, id, action, actor_opts)
    end
  end

  def run(["requirement", action, id], opts)
      when action in ~w(submit approve reject supersede) do
    with {:ok, root} <- required(opts, :store),
         {:ok, actor_opts} <- review_options(opts) do
      Lifecycle.review_requirement(root, id, action, actor_opts)
    end
  end

  def run(["assumption", action, id], opts)
      when action in ~w(attest test discharge invalidate supersede) do
    with {:ok, root} <- required(opts, :store),
         {:ok, actor_opts} <- review_options(opts),
         {:ok, evidence} <- optional_evidence(opts) do
      Lifecycle.revise_assumption(root, id, action, actor_opts ++ [evidence: evidence])
    end
  end

  def run(["inspect", kind, id], opts) when kind in @types do
    with {:ok, root} <- required(opts, :store) do
      case Keyword.get(opts, :revision) do
        nil -> Lifecycle.latest(root, kind, id)
        revision when is_integer(revision) and revision > 0 -> revision(root, kind, id, revision)
        _ -> {:error, :invalid_g03_revision}
      end
    end
  end

  def run(["history", kind, id], opts) when kind in @types do
    with {:ok, root} <- required(opts, :store), do: Lifecycle.history(root, kind, id)
  end

  def run(["receipt", id], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, receipt} <- Lifecycle.receipt(root, id) do
      case Keyword.get(opts, :out) do
        nil -> {:ok, receipt}
        path -> write_receipt(path, receipt)
      end
    end
  end

  def run(["motif", "propose", project, snapshot_id], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, actor} <- required(opts, :actor),
         {:ok, snapshot} <- BeamCompass.load(root, project, snapshot_id, 2),
         {:ok, input} <- Motif.retry_external_effect(snapshot) do
      Lifecycle.propose(root, input, [actor: actor, resolve_source: resolver(root)] ++ at(opts))
    end
  end

  def run(_, _), do: {:error, :invalid_g03_command}

  defp create(kind, file, opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, input} <- read_document(file),
         :ok <- check_input(kind, input) do
      write_record(kind, root, input, opts)
    end
  end

  defp write_record("candidate", root, input, opts) do
    with {:ok, actor} <- required(opts, :actor) do
      Lifecycle.propose(root, input, [actor: actor, resolve_source: resolver(root)] ++ at(opts))
    end
  end

  defp write_record(kind, root, input, opts) do
    with {:ok, actor_opts} <- review_options(opts) do
      options = actor_opts ++ [resolve_source: resolver(root)]

      case kind do
        "requirement" -> Lifecycle.draft_requirement(root, input, options)
        "assumption" -> Lifecycle.register_assumption(root, input, options)
        "obligation" -> Lifecycle.record_obligation(root, input, options)
      end
    end
  end

  defp revision(root, kind, id, number) do
    with {:ok, records} <- Lifecycle.history(root, kind, id) do
      case Enum.find(records, &(&1["revision"] == number)) do
        nil -> {:error, {:unresolved_g03_revision, kind, id, number}}
        record -> {:ok, record}
      end
    end
  end

  defp check_input(kind, input) when is_map(input) do
    if Enum.all?(Map.keys(input), &(&1 in @input_fields[kind])) and
         Enum.all?(@input_fields[kind], fn field ->
           field in ~w(context source_candidate_id evidence) or Map.has_key?(input, field)
         end) do
      :ok
    else
      {:error, {:invalid_g03_input_fields, kind}}
    end
  end

  defp check_input(kind, _), do: {:error, {:invalid_g03_input_fields, kind}}

  defp resolver(root) do
    fn ref ->
      with {:ok, snapshot} <- BeamCompass.load(root, ref["project_id"],
             ref["snapshot_id"], ref["upstream_schema_version"]),
           {:ok, object} <- BeamCompass.resolve(snapshot, ref) do
        {:ok, object}
      end
    end
  end

  defp review_options(opts) do
    with {:ok, actor} <- required(opts, :actor) do
      {:ok,
       [actor: actor, ack_human: Keyword.get(opts, :ack_human, false),
        replacement_id: Keyword.get(opts, :replacement)] ++ at(opts) ++
         [resolve_source: resolver(Keyword.get(opts, :store, ""))]}
    end
  end

  defp at(opts) do
    case Keyword.fetch(opts, :at) do
      {:ok, value} -> [at: value]
      :error -> []
    end
  end

  defp optional_evidence(opts) do
    case Keyword.fetch(opts, :evidence) do
      :error -> {:ok, []}
      {:ok, path} ->
        with {:ok, value} <- read_document(path),
             true <- is_list(value) do
          {:ok, value}
        else
          false -> {:error, :invalid_assumption_evidence_file}
          error -> error
        end
    end
  end

  defp read_document(path) when is_binary(path) do
    with {:ok, stat} <- File.stat(path),
         true <- stat.type == :regular and stat.size <= @max_bytes,
         {:ok, bytes} <- File.read(path),
         {:ok, decoded} <- JSON.decode(bytes) do
      {:ok, decoded}
    else
      false -> {:error, :invalid_g03_json_file}
      error -> error
    end
  end

  defp read_document(_), do: {:error, :invalid_g03_json_file}

  defp write_receipt(path, receipt) do
    with {:ok, bytes} <- JSON.encode(receipt),
         :ok <- File.write(path, bytes <> "\n", [:exclusive, :binary]) do
      {:ok, %{"command" => "g03 receipt", "exported_path" => path,
        "verification_status" => "unrun", "coverage_status" => "unassessed"}}
    end
  end

  defp required(opts, name) do
    case Keyword.get(opts, name) do
      v when is_binary(v) and byte_size(v) > 0 -> {:ok, v}
      _ -> {:error, {:missing_option, "--#{name}"}}
    end
  end
end
