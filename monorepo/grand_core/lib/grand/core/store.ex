defmodule Grand.Core.Store do
  @moduledoc """
  Append-only, JSON-only local store for the G01A prototype.

  Objects are published by linking a fsynced temporary file into an immutable
  destination; an existing differing payload is a conflict, never an overwrite.
  Paths derive from SHA-256 of validated IDs rather than user-supplied path text.
  Root directory is operator-owned, not taken from imported source JSON.
  """

  alias Grand.Core.JSON
  @max_file 4_000_000
  @categories ~w(snapshots requirements)

  @spec put(binary(), binary(), binary(), map()) :: {:ok, binary()} | {:error, term()}
  def put(root, category, key, value)
      when is_binary(root) and category in @categories and is_binary(key) do
    with true <- valid_key?(category, key),
         {:ok, encoded} <- JSON.encode(value),
         true <- byte_size(encoded) <= @max_file,
         :ok <- File.mkdir_p(parent(root, category, key)),
         {:ok, path} <- publish(location(root, category, key), encoded) do
      {:ok, path}
    else
      false -> {:error, :invalid_store_key_or_oversized_payload}
      error -> error
    end
  end

  def put(_, _, _, _), do: {:error, :invalid_store_key}

  @spec get(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def get(root, category, key)
      when is_binary(root) and category in @categories and is_binary(key) do
    path = location(root, category, key)

    with true <- valid_key?(category, key),
         {:ok, stat} <- File.stat(path),
         :ok <- size_check(stat),
         {:ok, bytes} <- File.read(path),
         {:ok, decoded} <- JSON.decode(bytes),
         true <- is_map(decoded) do
      {:ok, decoded}
    else
      false -> {:error, :invalid_store_key_or_stored_record}
      {:error, reason} -> {:error, reason}
    end
  end

  def get(_, _, _), do: {:error, :invalid_store_key}

  defp valid_key?("requirements", key) do
    case String.split(key, "@") do
      [id, revision] ->
        Grand.Core.valid_id?(id) and Regex.match?(~r/\A[1-9][0-9]*\z/, revision)

      _ ->
        false
    end
  end

  defp valid_key?("snapshots", key), do: Grand.Core.valid_id?(key)

  defp size_check(%File.Stat{size: size}) when size <= @max_file, do: :ok
  defp size_check(_), do: {:error, :stored_file_too_large}

  @doc "Lists saved revisions (numeric suffix) for a validated requirement ID."
  def revisions(root, id) when is_binary(root) and is_binary(id) do
    directory = parent(root, "requirements", id)

    case File.ls(directory) do
      {:ok, names} ->
        numbers =
          Enum.flat_map(names, &revision_number/1)

        {:ok, Enum.sort(numbers)}

      {:error, :enoent} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp revision_number(name) do
    case Regex.run(~r/\A([1-9][0-9]*)\.json\z/, name) do
      [_, value] -> [String.to_integer(value)]
      _ -> []
    end
  end

  @doc "Reads the highest revision; never mutates or silently rewrites earlier versions."
  def latest_requirement(root, id) do
    with true <- Grand.Core.valid_id?(id),
         {:ok, revisions} <- revisions(root, id),
         [_ | _] <- revisions,
         latest <- List.last(revisions),
         {:ok, requirement} <- get(root, "requirements", "#{id}@#{latest}"),
         {:ok, _} <- Grand.Core.validate("requirement", requirement),
         true <- requirement["id"] == id and requirement["revision"] == latest do
      {:ok, requirement}
    else
      false -> {:error, :invalid_requirement_identity}
      [] -> {:error, {:unresolved_requirement, id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parent(root, "requirements", key) do
    id = key |> String.split("@") |> hd()
    Path.join([root, "requirements", digest(id)])
  end

  defp parent(root, category, _key), do: Path.join(root, category)

  defp location(root, "requirements", key) do
    case String.split(key, "@") do
      [id, revision] -> Path.join(parent(root, "requirements", id), "#{revision}.json")
      _ -> Path.join(parent(root, "requirements", key), "invalid.json")
    end
  end

  defp location(root, category, key),
    do: Path.join(parent(root, category, key), digest(key) <> ".json")

  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp publish(destination, content) do
    temp = destination <> ".tmp-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

    with {:ok, io} <- File.open(temp, [:write, :binary, :exclusive]) do
      try do
        result =
          with :ok <- IO.binwrite(io, content),
               :ok <- :file.sync(io),
               :ok <- File.close(io) do
            case File.ln(temp, destination) do
              :ok -> {:ok, destination}
              {:error, :eexist} -> match_existing(destination, content)
              {:error, reason} -> {:error, {:store_publish_failed, reason}}
            end
          end

        result
      after
        File.close(io)
        File.rm(temp)
      end
    end
  end

  defp match_existing(path, content) do
    case File.read(path) do
      {:ok, ^content} -> {:ok, path}
      {:ok, _} -> {:error, :immutable_record_conflict}
      error -> error
    end
  end
end
