defmodule GrandAssurance.MixProject do
  use Mix.Project

  def project do
    [
      app: :grand_assurance,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: [{:grand_core, path: "../grand_core"}]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end
end
