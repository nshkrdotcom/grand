defmodule GrandCLI.MixProject do
  use Mix.Project

  def project do
    [
      app: :grand_cli,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: [
        {:grand_core, path: "../grand_core"},
        {:grand_beamcompass, path: "../grand_beamcompass"},
        {:grand_assurance, path: "../grand_assurance"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end
end
