defmodule GraphQLCop.Checks.AliasOverloading do
  @moduledoc """
  Check if a GraphQL endpoint allows alias overloading (100+ aliases in one op).
  """

  alias GraphQLCop.Utils

  @title "Alias Overloading"
  @description "Alias Overloading with 100+ aliases is allowed"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)

    # Build 101 aliases of __typename: alias0..alias100
    aliases =
      0..100
      |> Enum.map(fn i -> "alias#{i}: __typename" end)
      |> Enum.join("\n")

    payload = "query cop {\n#{aliases}\n}"

    resp =
      Utils.graph_query(url, %{
        proxy: proxy,
        headers: headers,
        payload: payload
      })

    curl_verify = Utils.curlify(resp)

    result = has_alias100?(resp.body)

    %{
      result: result,
      title: @title,
      description: @description,
      impact: "Denial of Service - /" <> last_path_segment_python_style(url),
      severity: "HIGH",
      color: "red",
      curl_verify: curl_verify
    }
  end

  # -- helpers --

  defp to_header_map(%{} = map), do: map
  defp to_header_map(list) when is_list(list), do: Map.new(list)
  defp to_header_map(_), do: %{}

  defp maybe_put_debug(headers, true), do: Map.put(headers, "X-GraphQL-Cop-Test", @title)
  defp maybe_put_debug(headers, _), do: headers

  # Accepts decoded map or raw JSON; checks for data.alias100
  defp has_alias100?(%{"data" => %{"alias100" => _}}), do: true

  defp has_alias100?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => %{"alias100" => _}}} -> true
      _ -> false
    end
  end

  defp has_alias100?(_), do: false

  # Match Python's `url.rsplit('/', 1)[-1]`.
  defp last_path_segment_python_style(url) when is_binary(url) do
    url
    |> String.split("/")
    |> List.last()
    |> case do
      nil -> ""
      seg -> seg
    end
  end
end
