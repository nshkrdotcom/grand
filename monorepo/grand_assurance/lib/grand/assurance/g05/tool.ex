defmodule Grand.Assurance.G05.Tool do
  @moduledoc """
  Small applicability identity of an *installed* external checker. This is not
  a tool distribution attestation. Changes to a runner module or toolchain pin
  invalidate scoped G05 results, without modifying historical receipts.
  """

  @roots %{"lynx" => "GRAND_LYNX_ROOT", "veil" => "GRAND_VEIL_ROOT"}
  @files %{
    "lynx" => ["lean-toolchain", "_build/dev/lib/lynx/ebin/Elixir.Lynx.Laws.beam"],
    "veil" => ["lean-toolchain", "Veil.lean"]
  }

  @spec identity(binary(), keyword()) :: map()
  def identity(engine, opts \\ []) when engine in ["lynx", "veil"] do
    root = Keyword.get(opts, :tool_root) || System.get_env(Map.fetch!(@roots, engine))

    if is_binary(root) and Path.type(root) == :absolute and File.dir?(root) do
      files =
        Enum.into(Map.fetch!(@files, engine), %{}, fn relative ->
          path = Path.join(root, relative)

          value =
            with {:ok, stat} <- File.lstat(path),
                 true <- stat.type == :regular and stat.size <= 4_000_000,
                 {:ok, bytes} <- File.read(path) do
              Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
            else
              _ -> nil
            end

          {relative, value}
        end)

      %{"root" => Path.expand(root), "files" => files, "available" => Enum.all?(files, fn {_, hash} -> is_binary(hash) end)}
    else
      %{"root" => nil, "files" => %{}, "available" => false}
    end
  end
end
