defmodule Grand.Assurance.G05.Tool do
  @moduledoc """
  Content identity of installed checker entry points, source closure and Grand
  adapters. This detects changed inputs for applicability, not hostile tool
  replacement, distribution attestation or production authentication.
  """

  @roots %{"lynx" => "GRAND_LYNX_ROOT", "veil" => "GRAND_VEIL_ROOT"}
  @files %{
    "lynx" => [
      "lean-toolchain",
      ".grand-tool.json",
      "Lean/lake-manifest.json",
      "_build/dev/lib/lynx/ebin/Elixir.Lynx.Laws.beam",
      "_build/dev/lib/lynx/ebin/Elixir.Lynx.Commands.beam",
      "_build/dev/lib/lynx/ebin/Elixir.Lynx.Translation.beam",
      "Lean/.lake/build/bin/Lynx-Runner"
    ],
    "veil" => [
      "lean-toolchain",
      ".grand-tool.json",
      "lake-manifest.json",
      "Veil.lean",
      ".lake/build/lib/lean/Veil/Frontend/DSL/Module/Util/ExecutionWorkflow.olean",
      ".lake/build/lib/lean/Veil/Core/Tools/ModelChecker/Concrete/Checker.olean"
    ]
  }

  @spec identity(binary(), keyword()) :: map()
  def identity(engine, opts \\ []) when engine in ["lynx", "veil"] do
    root = Keyword.get(opts, :tool_root) || System.get_env(Map.fetch!(@roots, engine))

    if is_binary(root) and Path.type(root) == :absolute and File.dir?(root) do
      files = Map.new(Map.fetch!(@files, engine), &{&1, digest(Path.join(root, &1))})
      files = Map.put(files, "source_closure", source_digest(root, engine))

      %{
        "root" => Path.expand(root),
        "files" => files,
        "grand_worker" => worker_identity(engine),
        "available" => Enum.all?(files, fn {_, hash} -> is_binary(hash) end)
      }
    else
      %{"root" => nil, "files" => %{}, "available" => false}
    end
  end

  defp digest(path) do
    with {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size <= 512_000_000 do
      path
      |> File.stream!(65_536)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
    else
      _ -> nil
    end
  rescue
    File.Error -> nil
  end

  defp source_digest(root, engine) do
    patterns =
      if engine == "lynx", do: ["lib/**/*.ex", "Lean/Lynx/**/*.lean"], else: ["Veil/**/*.lean"]

    entries =
      patterns
      |> Enum.flat_map(&Path.wildcard(Path.join(root, &1)))
      |> Enum.sort()
      |> Enum.map(&{Path.relative_to(&1, root), digest(&1)})

    if entries != [] and Enum.all?(entries, fn {_, hash} -> is_binary(hash) end) do
      entries
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
    end
  end

  defp worker_identity(engine) do
    adapter = if engine == "lynx", do: Grand.Assurance.G05.Lynx, else: Grand.Assurance.G05.Veil

    for mod <- [__MODULE__, Grand.Assurance.G05, Grand.Assurance.G04.Runner, adapter],
        into: %{} do
      {inspect(mod), Base.encode16(mod.module_info(:md5), case: :lower)}
    end
  end
end
