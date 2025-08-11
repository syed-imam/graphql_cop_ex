defmodule GraphQLCop.Checks.BatchQuery do
  @moduledoc """
  Check if a GraphQL endpoint allows array-based batching (10+ operations in one HTTP request).
  """

  alias GraphQLCop.Utils

  @title "Array-based Query Batching"
  @description "Batch queries allowed with 10+ simultaneous queries"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)

    # Build a batch array of >=10 operations
    batch_ops =
      1..10
      |> Enum.map(fn i ->
        %{
          "operationName" => "CopOp#{i}",
          "query" => "query CopOp#{i} { __typename }",
          "variables" => %{}
        }
      end)

    resp =
      Utils.graph_query(url, %{
        proxy: proxy,
        headers: headers,
        payload: batch_ops
      })

    curl_verify = Utils.curlify(resp)

    result =
      case resp.body do
        list when is_list(list) and length(list) >= 10 -> true
        _ -> false
      end

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
