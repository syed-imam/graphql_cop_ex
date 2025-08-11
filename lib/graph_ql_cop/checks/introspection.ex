defmodule GraphQLCop.Checks.Introspection do
  @moduledoc """
  Detect if GraphQL introspection is enabled by querying `__schema`.
  Flags HIGH severity if the server returns a non-empty list of types.
  """

  alias GraphQLCop.Utils

  @title "Introspection"
  @description "Introspection Query Enabled"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)

    q = """
    query cop {
      __schema {
        types {
          name
          fields { name }
        }
      }
    }
    """

    resp =
      Utils.graph_query(url, %{
        proxy: proxy,
        headers: headers,
        payload: q
      })

    curl_verify = Utils.curlify(resp)

    result = types_present?(resp.body)

    %{
      result: result,
      title: @title,
      description: @description,
      impact: "Information Leakage - /" <> last_path_segment_python_style(url),
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

  # Accept decoded map or raw JSON; true if data.__schema.types exists and is non-empty
  defp types_present?(%{} = decoded) do
    case get_in(decoded, ["data", "__schema", "types"]) do
      list when is_list(list) and list != [] -> true
      _ -> false
    end
  end

  defp types_present?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> types_present?(decoded)
      _ -> false
    end
  end

  defp types_present?(_), do: false

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
