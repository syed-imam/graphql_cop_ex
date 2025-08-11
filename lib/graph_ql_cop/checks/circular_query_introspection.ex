defmodule GraphQLCop.Checks.CircularQueryIntrospection do
  @moduledoc """
  Perform an introspection-driven circular query to detect DoS risk from
  deeply-nested `__schema -> types -> fields -> type -> fields ...` traversals.
  Flags HIGH if the server returns a large type list (>= 26 types).
  """

  alias GraphQLCop.Utils

  @title "Introspection-based Circular Query"
  @description "Circular-query using Introspection"

  @spec run(String.t(), String.t() | nil, map() | [{String.t(), String.t()}], boolean()) :: map()
  def run(url, proxy, headers, debug_mode \\ false) when is_binary(url) do
    headers =
      headers
      |> to_header_map()
      |> maybe_put_debug(debug_mode)

    # Deep, circular-style introspection query
    q = """
    query cop {
      __schema {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    type {
                      fields {
                        type { name }
                      }
                    }
                  }
                }
              }
            }
          }
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

    result = types_over_threshold?(resp.body, 25)

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

  # Accepts decoded map or raw JSON; checks if length(types) > threshold
  defp types_over_threshold?(%{} = decoded, threshold) do
    case get_in(decoded, ["data", "__schema", "types"]) do
      list when is_list(list) and length(list) > threshold -> true
      _ -> false
    end
  end

  defp types_over_threshold?(body, threshold) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> types_over_threshold?(decoded, threshold)
      _ -> false
    end
  end

  defp types_over_threshold?(_, _), do: false

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
