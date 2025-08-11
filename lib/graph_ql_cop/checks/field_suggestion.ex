defmodule GraphQLCop.Checks.FieldSuggestions do
  @moduledoc """
  Detects whether GraphQL field suggestions are enabled by provoking a typo-like error.
  If the server returns an error containing 'Did you mean', it indicates suggestion leakage.
  """

  alias GraphQLCop.Utils

  @title "Field Suggestions"
  @description "Field Suggestions are Enabled"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)

    # Intentionally invalid field "directive" under __schema to trigger suggestions
    q = "query cop { __schema { directive } }"

    resp =
      Utils.graph_query(url, %{
        proxy: proxy,
        headers: headers,
        payload: q
      })

    curl_verify = Utils.curlify(resp)

    result =
      resp.body
      |> extract_error_text()
      |> String.contains?("Did you mean")

    %{
      result: result,
      title: @title,
      description: @description,
      impact: "Information Leakage - /" <> last_path_segment_python_style(url),
      severity: "LOW",
      color: "blue",
      curl_verify: curl_verify
    }
  end

  # -- helpers --

  defp to_header_map(%{} = map), do: map
  defp to_header_map(list) when is_list(list), do: Map.new(list)
  defp to_header_map(_), do: %{}

  defp maybe_put_debug(headers, true), do: Map.put(headers, "X-GraphQL-Cop-Test", @title)
  defp maybe_put_debug(headers, _), do: headers

  # Extract concatenated error messages from decoded map or raw JSON string
  defp extract_error_text(%{"errors" => errors}) when is_list(errors) do
    errors
    |> Enum.map(&get_in(&1, ["message"]))
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp extract_error_text(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> extract_error_text(decoded)
      _ -> ""
    end
  end

  defp extract_error_text(_), do: ""

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
