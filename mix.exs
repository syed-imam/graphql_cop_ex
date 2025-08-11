defmodule GraphQLCop.MixProject do
  use Mix.Project

  def project do
    [
      app: :graphql_cop_ex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {GraphQLCop.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:httpoison, "~> 2.2"},
      {:jason, "~> 1.4"},
      {:absinthe, "~> 1.7"},
      {:bypass, "~> 2.1", only: :test},
      {:mock, "~> 0.3.8", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/syed-imam/graphql_cop_ex"
      }
    ]
  end
end
