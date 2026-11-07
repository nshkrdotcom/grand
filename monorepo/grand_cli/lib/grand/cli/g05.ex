defmodule Grand.CLI.G05 do
  @moduledoc """
  Explicit v2 G05 verification and conservative source-only change impact.
  `inspect` never runs code; `run` requires --execute and --allow-law-code for
  Lynx/Veil. Outputs are exclusive and never stored as G03 verdicts.
  """

  alias Grand.Assurance.G05, as: Verification
  alias Grand.Assurance.G05.Impact
  alias Grand.Core.JSON

  @max_bytes 2_000_000

  @doc "Dispatch inspect/run/applicability/impact without modifying an approved G03 record."
  def run([action, file], opts) when action in ~w(inspect run) do
    with {:ok, root} <- required(opts, :store),
         {:ok, manifest} <- load(file),
         {:ok, result} <- Verification.run(root, paths(manifest, file), policy(action, opts)) do
      maybe_write(result, Keyword.get(opts, :out))
    end
  end

  def run(["applicability", result_path, manifest_path], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, old} <- load(result_path),
         {:ok, manifest} <- load(manifest_path) do
      Verification.applicability(old, root, paths(manifest, manifest_path))
    end
  end

  def run(["impact", first_path, last_path, links_path], opts) do
    with {:ok, before} <- load(first_path),
         {:ok, after_snapshot} <- load(last_path),
         {:ok, %{"links" => links}} <- load(links_path),
         {:ok, result} <- Impact.compare(before, after_snapshot, links) do
      maybe_write(result, Keyword.get(opts, :out))
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_g05_impact_links}
    end
  end

  def run(_, _), do: {:error, :invalid_g05_command}

  defp policy("inspect", opts), do: Keyword.put(policy("run", opts), :execute, false)

  defp policy("run", opts) do
    [
      execute: Keyword.get(opts, :execute, false),
      allow_law_code: Keyword.get(opts, :allow_law_code, false),
      timeout_ms: Keyword.get(opts, :timeout_ms, 5_000),
      output_limit_bytes: Keyword.get(opts, :output_limit_bytes, 65_536)
    ]
  end

  defp paths(%{"law" => law} = manifest, file) when is_map(law) do
    base = Path.dirname(Path.expand(file))
    keys = ~w(file source_file support_file)

    updated =
      Enum.reduce(keys, law, fn key, item ->
        case Map.get(item, key) do
          value when is_binary(value) -> Map.put(item, key, Path.expand(value, base))
          _ -> item
        end
      end)

    Map.put(manifest, "law", updated)
  end

  defp paths(%{"model" => %{"file" => path}} = manifest, file)
       when is_binary(path) do
    put_in(manifest, ["model", "file"], Path.expand(path, Path.dirname(Path.expand(file))))
  end

  defp paths(manifest, _), do: manifest

  defp load(path) when is_binary(path) do
    with {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size <= @max_bytes,
         {:ok, content} <- File.read(path),
         {:ok, data} <- JSON.decode(content),
         true <- is_map(data) do
      {:ok, data}
    else
      false -> {:error, :unsafe_or_oversize_g05_json}
      {:error, reason} -> {:error, {:invalid_g05_json, reason}}
    end
  end

  defp load(_), do: {:error, :invalid_g05_json_path}

  defp maybe_write(result, nil), do: {:ok, result}

  defp maybe_write(result, path) when is_binary(path) do
    with {:ok, json} <- JSON.encode(result),
         :ok <- File.write(path, json <> "\n", [:exclusive, :binary]) do
      {:ok,
       %{"command" => "g05", "output" => path, "status" => Map.get(result, "status", "data_only")}}
    end
  end

  defp maybe_write(_, _), do: {:error, :invalid_g05_output_path}

  defp required(opts, name) do
    case Keyword.get(opts, name) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, {:missing_option, "--#{name}"}}
    end
  end
end
