defmodule Mix.Tasks.Grand do
  @shortdoc "Grand v1 JSON import, manual requirement link, and unrun export"
  @moduledoc "See Grand.CLI and the repository README for the exact command grammar."
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case Grand.CLI.run(args) do
      {:ok, output} ->
        case Grand.Core.encode(output) do
          {:ok, json} -> IO.puts(json)
          {:error, reason} -> Mix.raise("Grand JSON encoding error: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.raise("Grand command rejected: #{inspect(reason, limit: 12, printable_limit: 400)}")
    end
  end
end
