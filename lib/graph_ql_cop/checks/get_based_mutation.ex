defmodule GraphQLCop.Checks.GetBasedMutation do
  @moduledoc """
  Check if a GraphQL endpoint allows running a mutation via HTTP GET (possible CSRF).
  """

  @title "Mutation is allowed over GET (possible CSRF)"
  @description "GraphQL mutations allowed using the GET method"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)
      |> normalize_headers()

    q = "mutation cop { __typename }"

    # Build GET URL with ?query=<...>
    full_url = build_url_with_query(url, %{"query" => q})

    hackney_opts =
      case proxy do
        nil -> []
        "" -> []
        p -> [proxy: p]
      end

    resp =
      case HTTPoison.get(full_url, headers, hackney: hackney_opts) do
        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          %{
            status: status,
            body: decode_json(body),
            raw_body: body,
            request: %{
              url: full_url,
              headers: headers,
              # GET has no body payload
              payload: %{}
            }
          }

        {:error, %HTTPoison.Error{} = err} ->
          %{
            status: 0,
            body: %{},
            raw_body: Exception.message(err),
            request: %{
              url: full_url,
              headers: headers,
              payload: %{}
            }
          }
      end

    curl_verify = curlify_get(resp)

    result = has_typename?(resp.body)

    %{
      result: result,
      title: @title,
      description: @description,
      impact: "Possible Cross Site Request Forgery - /" <> last_path_segment_python_style(url),
      severity: "MEDIUM",
      color: "yellow",
      curl_verify: curl_verify
    }
  end

  # -- helpers --

  defp to_header_map(%{} = map), do: map
  defp to_header_map(list) when is_list(list), do: Map.new(list)
  defp to_header_map(_), do: %{}

  defp maybe_put_debug(headers, true), do: Map.put(headers, "X-GraphQL-Cop-Test", @title)
  defp maybe_put_debug(headers, _), do: headers

  defp normalize_headers(%{} = headers),
    do: Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)

  defp build_url_with_query(base, params) do
    sep = if String.contains?(base, "?"), do: "&", else: "?"
    base <> sep <> URI.encode_query(params)
  end

  defp decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> %{}
    end
  end

  # success if data.__typename exists (decoded map or raw JSON string)
  defp has_typename?(%{"data" => %{"__typename" => _}}), do: true

  defp has_typename?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => %{"__typename" => _}}} -> true
      _ -> false
    end
  end

  defp has_typename?(_), do: false

  # Build a curl that reflects a GET request with headers and querystring
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
