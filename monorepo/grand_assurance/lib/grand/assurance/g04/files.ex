defmodule Grand.Assurance.G04.Files do
  @moduledoc false

  @limit 256_000
  @extensions ~w(.lean .tla .cfg)

  @spec load(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def load(path, extension) when is_binary(path) and extension in @extensions do
    with true <- Path.extname(path) == extension,
         {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size <= @limit,
         {:ok, content} <- File.read(path),
         true <- byte_size(content) <= @limit and String.valid?(content) and
                   not String.contains?(content, <<0>>) do
      {:ok,
       %{
         "bytes" => content,
         "identity" => %{
           "path" => Path.expand(path),
           "sha256" => Base.encode16(:crypto.hash(:sha256, content), case: :lower),
           "size" => byte_size(content)
         }
       }}
    else
      false -> {:error, {:unsafe_or_oversize_verification_file, path}}
      {:error, reason} -> {:error, {:unreadable_verification_file, path, reason}}
    end
  end

  def load(_, _), do: {:error, :invalid_verification_file}

  @spec identifier?(term()) :: boolean()
  def identifier?(value) when is_binary(value) do
    byte_size(value) in 1..128 and
      Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_'.]*\z/, value)
  end

  def identifier?(_), do: false
end
