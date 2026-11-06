defmodule Grand.CLI do
  @moduledoc """
  Headless Grand G01A entry point. Use via `mix grand ...` from grand_cli.

  All import operations read serialized JSON only. No source code is loaded,
  compiled, evaluated or executed. Only explicit CLI `approve` changes a
  requirement's normative status (by adding a new revision).
  """

  alias Grand.Assurance
  alias Grand.BeamCompass
  alias Grand.Core
  alias Grand.Core.JSON

  @switches [
    project: :string,
    store: :string,
    snapshot: :string,
    fact: :string,
    actor: :string,
    at: :string,
    out: :string,
    ack_human: :boolean
  ]

  @usage """
  Run in monorepo/grand_cli (all options are long-form):
    mix grand import SNAPSHOT.json --project ID --store DIRECTORY
    mix grand link REQUIREMENT.json --project ID --snapshot ID --fact ID --actor human:ID --store DIRECTORY [--at ISO8601]
    mix grand approve REQUIREMENT_ID --actor human:ID --ack-human --store DIRECTORY [--at ISO8601]
    mix grand inspect requirement REQUIREMENT_ID --store DIRECTORY
    mix grand inspect snapshot PROJECT_ID SNAPSHOT_ID --store DIRECTORY
    mix grand inspect fact PROJECT_ID SNAPSHOT_ID FACT_ID --store DIRECTORY
    mix grand export REQUIREMENT_ID --project ID --store DIRECTORY [--out NEW_FILE]
  """

  @spec run([binary()]) :: {:ok, map()} | {:error, term()}
  def run(argv) when is_list(argv) do
    {options, positional, invalid} = OptionParser.parse(argv, strict: @switches)

    if invalid == [] do
      dispatch(positional, options)
    else
      {:error, {:invalid_cli_options, invalid}}
    end
  end

  defp dispatch(["help"], _opts), do: {:ok, %{"usage" => @usage}}

  defp dispatch(["import", path], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, project} <- required(opts, :project),
         {:ok, snapshot} <- BeamCompass.import_file(path, project_id: project),
         {:ok, _persisted_path} <- BeamCompass.store(snapshot, root) do
      {:ok,
       %{
         "command" => "import",
         "project_id" => project,
         "snapshot_id" => snapshot["snapshot_id"],
         "fact_count" => length(snapshot["upstream"]["facts"]),
         "source_sha256" => snapshot["source_sha256"],
         "epistemic_scope" => "syntactic_source_only"
       }}
    end
  end

  defp dispatch(["link", requirement_path], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, project} <- required(opts, :project),
         {:ok, snapshot_id} <- required(opts, :snapshot),
         {:ok, fact_id} <- required(opts, :fact),
         {:ok, actor} <- required(opts, :actor),
         {:ok, snapshot} <- BeamCompass.load(root, project, snapshot_id),
         {:ok, reference} <- BeamCompass.reference(snapshot, fact_id),
         {:ok, _fact} <- BeamCompass.resolve(snapshot, reference),
         {:ok, raw} <- safe_read(requirement_path),
         {:ok, requirement} <- Core.decode(raw, "requirement"),
         {:ok, linked} <-
           Assurance.link_requirement(requirement, reference, actor_and_at(actor, opts)),
         {:ok, _path} <- Assurance.save_requirement(root, linked) do
      {:ok,
       %{
         "command" => "link",
         "requirement_id" => linked["id"],
         "revision" => linked["revision"],
         "status" => linked["status"],
         "behavior_ref" => reference
       }}
    end
  end

  defp dispatch(["approve", id], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, actor} <- required(opts, :actor),
         true <- Keyword.get(opts, :ack_human, false) == true,
         {:ok, previous} <- Assurance.latest(root, id),
         {:ok, updated} <-
           Assurance.approve(previous, actor_and_at(actor, opts) ++ [ack_human: true]),
         {:ok, _path} <- Assurance.save_requirement(root, updated) do
      {:ok,
       %{
         "command" => "approve",
         "requirement_id" => id,
         "revision" => updated["revision"],
         "status" => updated["status"],
         "actor" => actor,
         "identity_assurance" => "self_attested_not_authenticated"
       }}
    else
      false -> {:error, :explicit_ack_human_required}
      error -> error
    end
  end

  defp dispatch(["inspect", "requirement", id], opts) do
    with {:ok, root} <- required(opts, :store), do: Assurance.latest(root, id)
  end

  defp dispatch(["inspect", "snapshot", project, id], opts) do
    with {:ok, root} <- required(opts, :store), do: BeamCompass.load(root, project, id)
  end

  defp dispatch(["inspect", "fact", project, snapshot_id, fact_id], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, snapshot} <- BeamCompass.load(root, project, snapshot_id),
         {:ok, reference} <- BeamCompass.reference(snapshot, fact_id),
         {:ok, fact} <- BeamCompass.resolve(snapshot, reference) do
      {:ok, %{"behavior_ref" => reference, "upstream_fact" => fact}}
    end
  end

  defp dispatch(["export", id], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, project} <- required(opts, :project),
         {:ok, requirement} <- Assurance.latest(root, id),
         [reference] <- Map.get(requirement, "behavior_refs", []),
         true <- reference["project_id"] == project,
         {:ok, snapshot} <- BeamCompass.load(root, project, reference["snapshot_id"]),
         {:ok, _fact} <- BeamCompass.resolve(snapshot, reference),
         {:ok, bundle} <-
           Assurance.unrun_bundle(requirement, reference, snapshot["source_sha256"]),
         {:ok, output} <- maybe_write_export(Keyword.get(opts, :out), bundle) do
      {:ok, output}
    else
      [] -> {:error, :requirement_has_no_source_ref}
      false -> {:error, :reference_wrong_project}
      error -> error
    end
  end

  defp dispatch(_, _), do: {:error, {:usage, @usage}}

  defp actor_and_at(actor, options) do
    case Keyword.fetch(options, :at) do
      {:ok, at} -> [actor: actor, at: at]
      :error -> [actor: actor]
    end
  end

  defp required(options, name) do
    case Keyword.get(options, name) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, {:missing_option, "--#{String.replace(Atom.to_string(name), "_", "-")}"}}
    end
  end

  defp safe_read(path) do
    with {:ok, stat} <- File.stat(path),
         true <- stat.size <= 4_000_000,
         {:ok, bytes} <- File.read(path) do
      {:ok, bytes}
    else
      false -> {:error, :requirement_file_too_large}
      error -> error
    end
  end

  defp maybe_write_export(nil, bundle), do: {:ok, bundle}

  defp maybe_write_export(path, bundle) do
    with {:ok, json} <- JSON.encode(bundle),
         :ok <- File.write(path, json <> "\n", [:exclusive, :binary]) do
      {:ok,
       %{
         "command" => "export",
         "exported_path" => path,
         "assurance_id" => bundle["assurance_record"]["id"],
         "verification_status" => "unrun",
         "coverage_status" => "unassessed"
       }}
    end
  end
end
