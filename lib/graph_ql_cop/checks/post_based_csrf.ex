defmodule GraphQLCop.Checks.PostBasedCSRF do
  @moduledoc """
  Check if a GraphQL endpoint accepts non-JSON (urlencoded) POST queries (possible CSRF).
  """

  @title "POST based url-encoded query (possible CSRF)"
  @description "GraphQL accepts non-JSON queries over POST"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    # Build headers as a map, add debug header (optional), and force form content type.
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)
      |> Map.put("Content-Type", "application/x-www-form-urlencoded")
      |> normalize_headers()

    q = "query cop { __typename }"
    form_body = URI.encode_query(%{"query" => q})

    hackney_opts =
      case proxy do
        nil -> []
        "" -> []
        p -> [proxy: p]
      end

    resp =
      case HTTPoison.post(url, form_body, headers, hackney: hackney_opts) do
        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          %{
            status: status,
            body: decode_json(body),
            raw_body: body,
            request: %{
              url: url,
              headers: headers,
              payload: form_body
            }
          }

        {:error, %HTTPoison.Error{} = err} ->
          %{
            status: 0,
            body: %{},
            raw_body: Exception.message(err),
            request: %{
              url: url,
              headers: headers,
              payload: form_body
            }
          }
      end

    curl_verify = curlify_post_urlencoded(resp)
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

  # Build a curl reflecting a POST urlencoded request with headers and data
  defp curlify_post_urlencoded(%{request: %{url: url, headers: headers, payload: form_body}}) do
    header_flags =
      headers
      |> Enum.map(fn {k, v} -> "-H #{shell_escape("#{k}: #{v}")}" end)
      |> Enum.join(" ")

    "curl -s -X POST #{shell_escape(url)} #{header_flags} --data #{shell_escape(form_body)}"
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
