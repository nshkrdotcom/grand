defmodule Grand.Assurance.G04.Verifier do
  @moduledoc """
  Replaceable external verification adapter. `prepare/2` reads explicitly
  selected files as data, `execute/2` is opt-in, and `normalize/2` inspects
  actual checker output rather than treating process exit 0 as proof.
  """

  @callback prepare(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback execute(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback normalize(map(), map()) :: {:ok, map()} | {:error, term()}
end
