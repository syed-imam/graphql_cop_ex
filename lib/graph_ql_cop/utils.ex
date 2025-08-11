defmodule GraphQLCop.Utils do
  @moduledoc """
  Minimal HTTP utilities for checks.
  """

  @type response :: %{
          status: non_neg_integer,
          body: map() | list() | nil,
          raw_body: binary(),
          request: %{
            url: binary(),
            headers: [{binary(), binary()}],
            payload: map()
          }
        }

  @doc """
  Sends a GraphQL POST request.

  Expected opts:
    - :headers -> map or list of {k, v}
    - :payload -> either a raw query string or a full JSON map
    - :proxy   -> optional proxy passed to hackney (e.g., "http://127.0.0.1:8080")
  """
  @spec graph_query(String.t(), map()) :: response()
  def graph_query(url, opts) when is_binary(url) and is_map(opts) do
    headers = Map.get(opts, :headers, %{}) |> normalize_headers() |> ensure_json_content_type()

    payload =
      case Map.get(opts, :payload) do
        q when is_binary(q) -> %{"query" => q}
        list when is_list(list) -> list
        %{} = map -> map
        _ -> %{}
      end

    hackney_opts =
      case Map.get(opts, :proxy) do
        nil -> []
        "" -> []
        proxy -> [proxy: proxy]
      end

    case HTTPoison.post(url, Jason.encode!(payload), headers, hackney: hackney_opts) do
      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        %{
          status: status,
          body: decode_json(body),
          raw_body: body,
          request: %{
            url: url,
            headers: headers,
            payload: payload
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
            payload: payload
          }
        }
    end
  end

  @doc """
  Builds a reproducible curl command for the last request.
  """
  @spec curlify(response()) :: String.t()
  def curlify(%{request: %{url: url, headers: headers, payload: payload}}) do
    header_flags =
      headers
      |> Enum.map(fn {k, v} -> "-H #{shell_escape("#{k}: #{v}")}" end)
      |> Enum.join(" ")

    data = Jason.encode!(payload)
    "curl -s -X POST #{shell_escape(url)} #{header_flags} --data #{shell_escape(data)}"
  end

  # -- helpers --

  defp decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> %{}
    end
  end

  defp normalize_headers(%{} = headers),
    do: Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)

  defp normalize_headers(list) when is_list(list),
    do:
      Enum.map(list, fn
        {k, v} -> {to_string(k), to_string(v)}
        other -> other
      end)

  defp ensure_json_content_type(headers) do
    case Enum.find(headers, fn {k, _} -> String.downcase(k) == "content-type" end) do
      nil -> [{"Content-Type", "application/json"} | headers]
      _ -> headers
    end
  end

  defp shell_escape(str) do
    escaped = String.replace(str, "'", "'\"'\"'")
    "'#{escaped}'"
  end
end
