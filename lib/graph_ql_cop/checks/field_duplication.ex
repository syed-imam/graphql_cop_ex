defmodule GraphQLCop.Checks.FieldDuplication do
  @moduledoc """
  Check if a GraphQL endpoint allows extreme field duplication (500 repeats of the same field).
  """

  alias GraphQLCop.Utils

  @title "Field Duplication"
  @description "Queries are allowed with 500 of the same repeated field"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)

    duplicated_string = String.duplicate("__typename \n", 500)
    q = "query cop { #{duplicated_string} }"

    resp =
      Utils.graph_query(url, %{
        proxy: proxy,
        headers: headers,
        payload: q
      })

    curl_verify = Utils.curlify(resp)

    result = has_typename?(resp.body)

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

  # Accept decoded map or raw JSON; success if data.__typename exists
  defp has_typename?(%{"data" => %{"__typename" => _}}), do: true

  defp has_typename?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => %{"__typename" => _}}} -> true
      _ -> false
    end
  end

  defp has_typename?(_), do: false

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
