defmodule Grand.BeamCompass do
  @moduledoc """
  JSON-only BeamCompass adapters. v1 and v2 are separate, version-checked paths.

  No target code, source anchors, Mix configuration or upstream runtime is opened
  or evaluated. v2 source evidence is descriptive, never observed execution.
  """

  alias Grand.BeamCompass.{Query, V1, V2}
  alias Grand.Core.JSON

  @max_bytes 4_000_000

  @doc "Read a bounded external JSON export, dispatching only on its declared version."
  @spec import_file(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def import_file(path, opts) when is_binary(path) and is_list(opts) do
    with {:ok, %{size: size}} <- File.stat(path),
         true <- size <= @max_bytes,
         {:ok, bytes} <- File.read(path),
         {:ok, decoded} <- JSON.decode(bytes, max_bytes: @max_bytes) do
      case decoded do
        %{"schema_version" => 1} -> V1.import_file(path, opts)
        %{"schema_version" => 2} -> V2.import_data(decoded, bytes, opts)
        %{"schema_version" => version} -> {:error, {:unsupported_schema_version, version}}
        _ -> V1.validate_v1(decoded)
      end
    else
      false -> {:error, :invalid_project_or_oversized_input}
      {:error, _} = error -> error
    end
  end

  def import_file(_, _), do: {:error, :invalid_import_arguments}

  defdelegate validate_v1(snapshot), to: V1
  defdelegate valid_relative_path?(path), to: V1
  defdelegate snapshot_key(project_id, snapshot_id), to: V1

  @doc "Resolve legacy v1 fact references without silently converting them to v2."
  def reference(snapshot, fact_id) do
    case version(snapshot) do
      1 -> V1.reference(snapshot, fact_id)
      2 -> {:error, :v2_object_kind_required}
      _ -> {:error, :unsupported_import_envelope}
    end
  end

  @doc "Construct a v2 entity, relation or evidence reference (kind is mandatory)."
  def reference(snapshot, kind, object_id) do
    case version(snapshot) do
      2 -> V2.reference(snapshot, kind, object_id)
      _ -> {:error, :v2_snapshot_required}
    end
  end

  @doc "Exact resolution of v1 or v2 refs; never cross-join by semantic key."
  def resolve(snapshot, reference) do
    case version(snapshot) do
      1 -> V1.resolve(snapshot, reference)
      2 -> V2.resolve(snapshot, reference)
      _ -> {:error, :unsupported_import_envelope}
    end
  end

  @doc "Validate a persisted import, including its upstream canonical hash."
  def validate_envelope(envelope) do
    case version(envelope) do
      1 -> V1.validate_envelope(envelope)
      2 -> V2.validate_envelope(envelope)
      _ -> {:error, :unsupported_import_envelope}
    end
  end

  @doc "Immutable storage in a version-specific collection; v1 layout is unchanged."
  def store(snapshot, root) do
    case version(snapshot) do
      1 -> V1.store(snapshot, root)
      2 -> V2.store(snapshot, root)
      _ -> {:error, :unsupported_import_envelope}
    end
  end

  @doc "Auto-load v2 when present, otherwise preserve the existing v1 lookup."
  def load(root, project_id, snapshot_id) do
    case V2.load(root, project_id, snapshot_id) do
      {:error, :enoent} -> V1.load(root, project_id, snapshot_id)
      {:error, :invalid_v2_snapshot_key} -> V1.load(root, project_id, snapshot_id)
      other -> other
    end
  end

  @doc "Explicit version selection; avoids accidental cross-version fallback."
  def load(root, project_id, snapshot_id, version) do
    case version do
      1 -> V1.load(root, project_id, snapshot_id)
      2 -> V2.load(root, project_id, snapshot_id)
      _ -> {:error, {:unsupported_schema_version, version}}
    end
  end

  @doc "Bounded query over v2 imported data, not an upstream P03 projection."
  def query(snapshot, opts), do: Query.run(snapshot, opts)

  defp version(%{"schema_version" => version}), do: version
  defp version(_), do: nil
end
