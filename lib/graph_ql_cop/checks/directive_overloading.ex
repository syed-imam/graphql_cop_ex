defmodule GraphQLCop.Checks.DirectiveOverloading do
  @moduledoc """
  Check if a GraphQL endpoint allows duplicated/overloaded directives in a single field.
  Flags HIGH if the response returns exactly 10 directive-related errors, mirroring the Python check.
  """

  alias GraphQLCop.Utils

  @title "Directive Overloading"
  @description "Multiple duplicated directives allowed in a query"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)

    # Ten duplicated, invalid directives on __typename
    q = "query cop { __typename @aa@aa@aa@aa@aa@aa@aa@aa@aa@aa }"

    resp =
      Utils.graph_query(url, %{
        proxy: proxy,
        headers: headers,
        payload: q
      })

    curl_verify = Utils.curlify(resp)
    result = has_exactly_ten_errors?(resp.body)

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

  # Accepts decoded map or raw JSON string; returns true if errors length == 10
  defp has_exactly_ten_errors?(%{"errors" => errors}) when is_list(errors),
    do: length(errors) == 10

  defp has_exactly_ten_errors?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"errors" => errors}} when is_list(errors) -> length(errors) == 10
      _ -> false
    end
  end

  defp has_exactly_ten_errors?(_), do: false

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
