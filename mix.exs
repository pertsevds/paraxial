defmodule Paraxial.MixProject do
  use Mix.Project

  def project do
    [
      app: :paraxial,
      version: "2.3.1",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Paraxial",
      source_url: "https://github.com/paraxialio/paraxial",
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Paraxial.Application, []}
    ]
  end

  defp docs do
    [
      main: "getting_started",
      extra_sections: "GUIDES",
      extras: extras()
    ]
  end

  defp aliases do
    [docs: ["docs", &copy_images/1]]
  end

  defp copy_images(_) do
    File.cp_r("assets", "doc/assets", fn source, destination ->
      IO.gets("Overwriting #{destination} by #{source}. Type y to confirm. ") == "y\n"
    end)
  end

  defp extras do
    [
      "documentation/getting_started.md",
      "documentation/user_manual.md",
      "documentation/install.md",
      "documentation/code_scans.md",
      "README.md",
      "documentation/agent.md",
      "documentation/cloud_ips.md",
      "documentation/CHANGELOG.md"
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:httpoison, "~> 1.0"},
      {:inet_cidr, "~> 1.0"},
      {:iptrie, "~> 0.8.0"},
      {:ex_doc, "~> 0.28.4", only: :dev},
      {:sobelow, "~> 0.12.1"},
      {:mix_audit, "~> 2.1"}
    ]
  end

  defp description() do
    "The Paraxial.io Agent."
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/paraxialio/paraxial"}
    ]
  end
end
