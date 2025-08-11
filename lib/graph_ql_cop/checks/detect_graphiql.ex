defmodule GraphQLCop.Checks.DetectGraphiQL do
  @moduledoc """
  Detect if a GraphQL IDE is exposed (GraphiQL/Playground).
  Sends a GET with Accept: text/html and searches the response body
  for known IDE markers.
  """

  @title "GraphQL IDE"
  @description "GraphiQL Explorer/Playground Enabled"

  @heuristics [
    "graphiql.min.css",
    "GraphQL Playground",
    "GraphiQL",
    "graphql-playground"
  ]

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    # Start with user-provided headers, add debug if requested,
    # then force Accept: text/html (without mutating caller's structure).
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)
      |> Map.put("Accept", "text/html")
      |> normalize_headers()

    hackney_opts =
      case proxy do
        nil -> []
        "" -> []
        p -> [proxy: p]
      end

    resp =
      case HTTPoison.get(url, headers, hackney: hackney_opts) do
        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          %{
            status: status,
            # keep raw body string; we only need to search it
            body: body,
            raw_body: body,
            request: %{
              url: url,
              headers: headers,
              # GET has no body
              payload: %{}
            }
          }

        {:error, %HTTPoison.Error{} = err} ->
          %{
            status: 0,
            body: "",
            raw_body: Exception.message(err),
            request: %{
              url: url,
              headers: headers,
              payload: %{}
            }
          }
      end

    curl_verify = curlify_get(resp)
    result = contains_ide_marker?(resp.body)

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

  defp maybe_put_debug(headers, true),
    do: Map.put(headers, "X-GraphQL-Cop-Test", @title)

  defp maybe_put_debug(headers, _), do: headers

  defp normalize_headers(%{} = headers),
    do: Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)

  defp contains_ide_marker?(body) when is_binary(body) do
    Enum.any?(@heuristics, &String.contains?(body, &1))
  end

  defp contains_ide_marker?(_), do: false

  # Build a curl reflecting a GET request with headers
  defp curlify_get(%{request: %{url: url, headers: headers}}) do
    header_flags =
      headers
      |> Enum.map(fn {k, v} -> "-H #{shell_escape("#{k}: #{v}")}" end)
      |> Enum.join(" ")

    "curl -s -X GET #{shell_escape(url)} #{header_flags}"
  end

  defp shell_escape(str) do
    escaped = String.replace(str, "'", "'\"'\"'")
    "'#{escaped}'"
  end

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
