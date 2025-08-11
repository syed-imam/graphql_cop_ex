defmodule GraphQLCop.Checks.TraceMode do
  @moduledoc """
  Detect if GraphQL tracing is enabled by looking for `extensions.tracing`
  in the response (typically under `errors[0].extensions.tracing` or top-level).
  """

  alias GraphQLCop.Utils

  @title "Trace Mode"
  @description "Tracing is Enabled"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)

    q = "query cop { __typename }"

    resp =
      Utils.graph_query(url, %{
        proxy: proxy,
        headers: headers,
        payload: q
      })

    curl_verify = Utils.curlify(resp)
    result = tracing_enabled?(resp.body)

    %{
      result: result,
      title: @title,
      description: @description,
      impact: "Information Leakage - /" <> last_path_segment_python_style(url),
      severity: "INFO",
      color: "green",
      curl_verify: curl_verify
    }
  end

  # -- helpers --

  defp to_header_map(%{} = map), do: map
  defp to_header_map(list) when is_list(list), do: Map.new(list)
  defp to_header_map(_), do: %{}

  defp maybe_put_debug(headers, true), do: Map.put(headers, "X-GraphQL-Cop-Test", @title)
  defp maybe_put_debug(headers, _), do: headers

  # Determine whether tracing info is present (decoded map or raw JSON string).
  defp tracing_enabled?(%{} = decoded) do
    cond do
      not is_nil(get_in(decoded, ["errors", Access.at(0), "extensions", "tracing"])) -> true
      not is_nil(get_in(decoded, ["extensions", "tracing"])) -> true
      true ->
        s = decoded |> inspect() |> String.downcase()
        String.contains?(s, "\"extensions\"") and String.contains?(s, "\"tracing\"")
    end
  end

  defp tracing_enabled?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> tracing_enabled?(decoded)
      _ ->
        s = String.downcase(body)
        String.contains?(s, "\"extensions\"") and String.contains?(s, "\"tracing\"")
    end
  end

  defp tracing_enabled?(_), do: false

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
