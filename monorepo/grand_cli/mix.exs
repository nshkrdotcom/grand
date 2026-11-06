defmodule GrandCLI.MixProject do
  use Mix.Project

  def project do
    [
      app: :grand_cli,
      version: "0.1.0",
      elixir: "~> 1.15",
      name: "Grand CLI",
      description:
        "Orchestration and Mix tasks for Grand normative requirements and assurance pipelines.",
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
      logo: "assets/grand_cli.svg",
      assets: %{"assets" => "assets"},
      source_ref: "main",
      source_url_pattern:
        "https://github.com/nshkrdotcom/grand/blob/main/monorepo/grand_cli/%{path}#L%{line}",
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
        {"Public API", [Grand.CLI]},
        {"Mix tasks", [Mix.Tasks.Grand]}
      ]
    ]
  end

  defp poncho_dependency(app) do
    if File.dir?(Path.expand("../#{app}", __DIR__)) and System.get_env("HEX_BUILD") != "true" do
      {app, "~> 0.1.0", path: "../#{app}", override: true}
    else
      {app, "~> 0.1.0"}
    end
  end

  defp deps do
    [
      poncho_dependency(:grand_core),
      poncho_dependency(:grand_beamcompass),
      poncho_dependency(:grand_assurance),
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
