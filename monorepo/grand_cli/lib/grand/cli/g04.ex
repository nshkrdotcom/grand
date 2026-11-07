defmodule Grand.CLI.G04 do
  @moduledoc """
  G04 explicit verification CLI. JSON documents are data; no checker runs in
  `inspect`, and `run` also stays unrun unless `--execute` is provided.
  Neither command changes a G03 approval, obligation or historical receipt.
  """

  alias Grand.Assurance.G04, as: Verification
  alias Grand.Core.JSON

  @max_bytes 1_000_000

  @doc "Dispatch a G04 inspect/run/applicability command."
  def run([action, file], opts) when action in ~w(inspect run) do
    with {:ok, root} <- required(opts, :store),
         {:ok, manifest} <- load(file),
         {:ok, result} <- Verification.run(root, paths(manifest, file), policy(action, opts)) do
      maybe_write(result, Keyword.get(opts, :out))
    end
  end

  def run(["applicability", result_file, manifest_file], opts) do
    with {:ok, root} <- required(opts, :store),
         {:ok, result} <- load(result_file),
         {:ok, manifest} <- load(manifest_file),
         {:ok, status} <- Verification.applicability(result, root, paths(manifest, manifest_file)) do
      {:ok, %{"applicability" => status}}
    end
  end

  def run(_, _), do: {:error, :invalid_g04_command}

  defp policy("inspect", opts), do: Keyword.put(policy("run", opts), :execute, false)

  defp policy("run", opts) do
    [
      execute: Keyword.get(opts, :execute, false),
      allow_law_code: Keyword.get(opts, :allow_law_code, false),
      tlc_jar: Keyword.get(opts, :tlc_jar),
      timeout_ms: Keyword.get(opts, :timeout_ms, 5_000),
      output_limit_bytes: Keyword.get(opts, :output_limit_bytes, 65_536)
    ]
  end

  defp paths(%{"law" => %{"file" => path} = law} = manifest, file) when is_binary(path) do
    %{manifest | "law" => %{law | "file" => Path.expand(path, Path.dirname(file))}}
  end

  defp paths(%{"model" => %{"file" => path, "config_file" => config} = model} = manifest, file)
       when is_binary(path) and is_binary(config) do
    base = Path.dirname(file)

    %{
      manifest
      | "model" => %{
          model
          | "file" => Path.expand(path, base),
            "config_file" => Path.expand(config, base)
        }
    }
  end

  defp paths(manifest, _file), do: manifest

  defp load(path) when is_binary(path) do
    with {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size <= @max_bytes,
         {:ok, content} <- File.read(path),
         {:ok, document} <- JSON.decode(content),
         true <- is_map(document) do
      {:ok, document}
    else
      false -> {:error, :unsafe_or_oversize_g04_json}
      {:error, reason} -> {:error, {:invalid_g04_json, reason}}
    end
  end

  defp load(_), do: {:error, :invalid_g04_json_path}

  defp maybe_write(result, nil), do: {:ok, result}

  defp maybe_write(result, path) when is_binary(path) do
    with {:ok, json} <- JSON.encode(result),
         :ok <- File.write(path, json <> "\n", [:exclusive, :binary]) do
      {:ok, %{"command" => "g04", "output" => path, "status" => result["status"]}}
    end
  end

  defp maybe_write(_, _), do: {:error, :invalid_g04_output_path}

  defp required(opts, name) do
    case Keyword.get(opts, name) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, {:missing_option, "--#{name}"}}
    end
  end
end
