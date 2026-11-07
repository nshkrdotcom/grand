defmodule Grand.CLI do
  @moduledoc """
  Headless Grand versioned JSON entry point. Use via `mix grand ...` from grand_cli.

  All import operations read serialized JSON only. No source code is loaded,
  compiled, evaluated or executed. Only explicit CLI `approve` changes a
  requirement's normative status (by adding a new revision).
  """

  alias Grand.Assurance
  alias Grand.CLI.G03, as: G03CLI
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
    ack_human: :boolean,
    schema: :integer,
    focus: :string,
    budget: :integer,
    lens: :string,
    preserve: :string,
    replacement: :string,
    evidence: :string,
    revision: :integer
  ]

  @usage """
  Run in monorepo/grand_cli (all options are long-form):
    mix grand import SNAPSHOT.json --project ID --store DIRECTORY [--schema 1|2]
    mix grand link REQUIREMENT.json --project ID --snapshot ID --fact ID --actor human:ID --store DIRECTORY [--at ISO8601]
    mix grand approve REQUIREMENT_ID --actor human:ID --ack-human --store DIRECTORY [--at ISO8601]
    mix grand inspect requirement REQUIREMENT_ID --store DIRECTORY
    mix grand inspect snapshot PROJECT_ID SNAPSHOT_ID --store DIRECTORY [--schema 1|2]
    mix grand inspect fact PROJECT_ID SNAPSHOT_ID FACT_ID --store DIRECTORY
    mix grand inspect entity|relation|evidence PROJECT_ID SNAPSHOT_ID OBJECT_ID --store DIRECTORY [--schema 2]
    mix grand query PROJECT_ID SNAPSHOT_ID --focus ENTITY_ID [--lens neighbors|connected|effects] [--budget N] [--preserve entity=ID] [--preserve relation=ID] --store DIRECTORY [--out NEW_FILE]
    mix grand export snapshot PROJECT_ID SNAPSHOT_ID --schema 2 --store DIRECTORY --out NEW_FILE
    mix grand export REQUIREMENT_ID --project ID --store DIRECTORY [--out NEW_FILE]
    mix grand g03 propose CANDIDATE.json --store DIR --actor agent:ID
    mix grand g03 motif propose PROJECT SNAPSHOT --store DIR --actor agent:ID
    mix grand g03 candidate reject|supersede ID --store DIR --actor human:ID --ack-human [--replacement ID]
    mix grand g03 requirement draft REQUIREMENT.json --store DIR --actor human:ID --ack-human
    mix grand g03 requirement submit|approve|reject|supersede ID --store DIR --actor human:ID --ack-human
    mix grand g03 assumption register ASSUMPTION.json --store DIR --actor human:ID --ack-human
    mix grand g03 assumption attest|test|discharge|invalidate|supersede ID --store DIR --actor human:ID --ack-human [--evidence JSON_LIST] [--replacement ID]
    mix grand g03 obligation create OBLIGATION.json --store DIR --actor human:ID --ack-human
    mix grand g03 inspect candidate|requirement|assumption|obligation ID --store DIR [--revision N]
    mix grand g03 history candidate|requirement|assumption|obligation ID --store DIR
    mix grand g03 receipt OBLIGATION_ID --store DIR [--out NEW_FILE]
  """

  @spec run([binary()]) :: {:ok, term()} | {:error, term()}
  def run(argv) when is_list(argv) do
    {options, positional, invalid} = OptionParser.parse(argv, strict: @switches)

    if invalid == [] do
      dispatch(positional, options)
    else
      {:error, {:invalid_cli_options, invalid}}
    end
  end

  defp dispatch(["help"], _opts), do: {:ok, %{"usage" => @usage}}

  defp dispatch(["g03" | args], opts), do: G03CLI.run(args, opts)

  defp dispatch(["import", path], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, project} <- required(opts, :project),
         {:ok, snapshot} <- BeamCompass.import_file(path, project_id: project),
         :ok <- expected_version(snapshot, opts),
         {:ok, _persisted_path} <- BeamCompass.store(snapshot, root) do
      if snapshot["schema_version"] == 1 do
        {:ok,
         %{
           "command" => "import",
           "project_id" => project,
           "snapshot_id" => snapshot["snapshot_id"],
           "fact_count" => length(snapshot["upstream"]["facts"]),
           "source_sha256" => snapshot["source_sha256"],
           "epistemic_scope" => "syntactic_source_only"
         }}
      else
        {:ok,
         %{
           "command" => "import",
           "schema_version" => 2,
           "project_id" => project,
           "snapshot_id" => snapshot["snapshot_id"],
           "entity_count" => length(snapshot["upstream"]["entities"]),
           "relation_count" => length(snapshot["upstream"]["relations"]),
           "evidence_count" => length(snapshot["upstream"]["evidence"]),
           "source_sha256" => snapshot["source_sha256"],
           "epistemic_scope" => "source_only_no_runtime_claim"
         }}
      end
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
    with {:ok, root} <- required(opts, :store), do: load_version(root, project, id, opts)
  end

  defp dispatch(["inspect", "fact", project, snapshot_id, fact_id], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, snapshot} <- BeamCompass.load(root, project, snapshot_id),
         {:ok, reference} <- BeamCompass.reference(snapshot, fact_id),
         {:ok, fact} <- BeamCompass.resolve(snapshot, reference) do
      {:ok, %{"behavior_ref" => reference, "upstream_fact" => fact}}
    end
  end

  defp dispatch(["inspect", kind, project, snapshot_id, id], opts)
       when kind in ~w(entity relation evidence) do
    with :ok <- require_v2(opts),
         {:ok, root} <- required(opts, :store),
         {:ok, snapshot} <- BeamCompass.load(root, project, snapshot_id, 2),
         {:ok, reference} <- BeamCompass.reference(snapshot, kind, id),
         {:ok, object} <- BeamCompass.resolve(snapshot, reference) do
      {:ok, %{"behavior_ref" => reference, "upstream_object" => object}}
    end
  end

  defp dispatch(["query", project, snapshot_id], opts) do
    with :ok <- require_v2(opts),
         {:ok, root} <- required(opts, :store),
         {:ok, focus} <- required(opts, :focus),
         {:ok, preserve} <- parse_preserve(opts),
         {:ok, snapshot} <- BeamCompass.load(root, project, snapshot_id, 2),
         {:ok, query} <-
           BeamCompass.query(snapshot,
             focus: focus,
             budget: Keyword.get(opts, :budget, 32),
             lens: Keyword.get(opts, :lens, "neighbors"),
             preserve: preserve
           ) do
      query_output(Keyword.get(opts, :out), query)
    end
  end

  defp dispatch(["export", "snapshot", project, snapshot_id], opts) do
    with :ok <- require_v2(opts),
         {:ok, root} <- required(opts, :store),
         {:ok, path} <- required(opts, :out),
         {:ok, snapshot} <- BeamCompass.load(root, project, snapshot_id, 2),
         {:ok, _} <- write_document(path, snapshot["upstream"]) do
      {:ok,
       %{
         "command" => "export snapshot",
         "exported_path" => path,
         "project_id" => project,
         "snapshot_id" => snapshot_id,
         "format" => "beamcompass.snapshot",
         "epistemic_scope" => "source_only_no_runtime_claim"
       }}
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

  defp query_output(nil, query), do: {:ok, query}

  defp query_output(path, query) do
    with {:ok, _} <- write_document(path, query) do
      {:ok, %{"command" => "query", "exported_path" => path, "receipt" => query["receipt"]}}
    end
  end

  defp load_version(root, project, id, opts) do
    case Keyword.get(opts, :schema) do
      nil -> BeamCompass.load(root, project, id)
      version -> BeamCompass.load(root, project, id, version)
    end
  end

  defp expected_version(snapshot, opts) do
    actual = snapshot["schema_version"]

    case Keyword.get(opts, :schema) do
      nil -> :ok
      ^actual -> :ok
      version -> {:error, {:schema_version_mismatch, version, actual}}
    end
  end

  defp require_v2(opts) do
    case Keyword.get(opts, :schema, 2) do
      2 -> :ok
      version -> {:error, {:v2_schema_required, version}}
    end
  end

  defp parse_preserve(opts) do
    opts
    |> Keyword.get_values(:preserve)
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, entries} ->
      case String.split(item, "=", parts: 2) do
        [kind, id] when kind in ~w(entity relation) and byte_size(id) > 0 ->
          {:cont, {:ok, [%{"object_kind" => kind, "object_id" => id} | entries]}}

        _ ->
          {:halt, {:error, {:invalid_preserve_option, item}}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      other -> other
    end
  end

  defp write_document(path, data) do
    with {:ok, json} <- JSON.encode(data),
         :ok <- File.write(path, json <> "\n", [:exclusive, :binary]) do
      {:ok, path}
    end
  end

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
