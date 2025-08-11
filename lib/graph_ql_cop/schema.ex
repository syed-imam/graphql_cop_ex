defmodule GraphQLCop.Schema do
  use Absinthe.Schema

  @doc """
  Convenience helper to run a GraphQL query against this schema.

  Example:
    GraphQLCop.Schema.run("{ hello }")
  """
  def run(query, vars \\ %{}) when is_binary(query) and is_map(vars) do
    Absinthe.run(query, __MODULE__, variables: vars)
  end

  query do
    @desc "Simple liveness check"
    field :status, non_null(:string) do
      resolve(fn _, _, _ -> {:ok, "ok"} end)
    end

    @desc "Returns a constant greeting"
    field :hello, non_null(:string) do
      resolve(fn _, _, _ -> {:ok, "world"} end)
    end

    @desc "Echoes the provided input"
    field :echo, :string do
      arg(:input, non_null(:string))
      resolve(fn _, %{input: input}, _ -> {:ok, input} end)
    end
  end
end
