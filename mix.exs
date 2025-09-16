defmodule Pigeon.MixProject do
  use Mix.Project

  def project do
    [
      app: :pigeon,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),

      # Docs
      name: "Pigeon",
      description: "Generic Distributed Work Processing Framework",
      source_url: "https://github.com/your-org/pigeon",
      homepage_url: "https://github.com/your-org/pigeon",
      docs: [
        main: "Pigeon",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl, :inets],
      mod: {Pigeon.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:finch, "~> 0.18"},

      # HTTP Server
      {:plug, "~> 1.15"},
      {:bandit, "~> 1.0"},

      # Infrastructure
      {:ex_aws, "~> 2.4"},
      {:ex_aws_ec2, "~> 2.0"},
      {:hackney, "~> 1.20"},

      # CLI
      {:optimus, "~> 0.3"},

      # Development
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp escript do
    [main_module: Pigeon.CLI]
  end
end