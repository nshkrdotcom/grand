defmodule GrandCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :grand_core,
      version: "0.1.0",
      elixir: "~> 1.20.5",
      name: "Grand Core",
      description:
        "Deterministic JSON codec, immutable content-addressed storage, and foundational records for Grand.",
      source_url: "https://github.com/nshkrdotcom/grand",
      homepage_url: "https://github.com/nshkrdotcom/grand",
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/nshkrdotcom/grand"},
      files: [
        "lib",
        "mix.exs",
        ".formatter.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "assets/*"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/grand_core.svg",
      assets: %{"assets" => "assets"},
      source_ref: "main",
      source_url_pattern:
        "https://github.com/nshkrdotcom/grand/blob/main/monorepo/grand_core/%{path}#L%{line}",
      extras: [
        {"README.md", [title: "Overview"]},
        {"CHANGELOG.md", [title: "Changelog"]},
        {"LICENSE", [title: "License"]}
      ],
      groups_for_extras: [
        {"Getting started", ["README.md"]},
        {"Project", ["CHANGELOG.md", "LICENSE"]}
      ],
      groups_for_modules: [
        {"Public API", [Grand.Core]},
        {"Storage", [Grand.Core.Store]},
        {"Codec & Validation", [Grand.Core.JSON]}
      ]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
