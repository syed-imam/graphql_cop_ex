defmodule GraphQLCop.Checks.UnhandledErrorDetection do
  @moduledoc """
  Detects unhandled server exceptions leaked via GraphQL error extensions.
  Marks INFO if `errors[0].extensions.exception` (or similar) appears in the response.
  """

  alias GraphQLCop.Utils

  @title "Unhandled Errors Detection"
  @description "Exception errors are not handled"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)

    # Intentionally invalid query to provoke an error with extensions.exception
    q = "qwerty cop { abc }"

    resp =
      Utils.graph_query(url, %{
        proxy: proxy,
        headers: headers,
        payload: q
      })

    curl_verify = Utils.curlify(resp)
    result = exception_leaked?(resp.body)

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

  # Detect presence of exception in error extensions (decoded map or raw JSON/string)
  defp exception_leaked?(%{} = decoded) do
    cond do
      not is_nil(get_in(decoded, ["errors", Access.at(0), "extensions", "exception"])) ->
        true

      # Some servers might place it at top-level extensions (rare, but cheap to check)
      not is_nil(get_in(decoded, ["extensions", "exception"])) ->
        true

      true ->
        # Fallback: mimic Python's str(dict).lower() contains "'extensions': {'exception':"
        decoded
        |> inspect()
        |> String.downcase()
        |> String.contains?("extensions")
        |> case do
          true ->
            decoded
            |> inspect()
            |> String.downcase()
            |> String.contains?("exception")

          false ->
            false
        end
    end
  end

  defp exception_leaked?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        exception_leaked?(decoded)

      _ ->
        s = String.downcase(body)
        String.contains?(s, "\"extensions\"") and String.contains?(s, "\"exception\"")
    end
  end

  defp exception_leaked?(_), do: false

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
