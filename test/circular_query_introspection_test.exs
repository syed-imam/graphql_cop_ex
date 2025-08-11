defmodule GraphQLCop.Checks.CircularQueryIntrospectionTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.CircularQueryIntrospection

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}

  test "returns result: true when types length > 25 (decoded map body)" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: _h, payload: payload, proxy: proxy} ->
        # Validate call
        assert url == @url
        assert proxy == @proxy
        assert is_binary(payload)
        # Rough sanity checks on the introspection query
        assert String.contains?(payload, "__schema")
        assert String.contains?(payload, "types")
        assert String.contains?(payload, "fields")
        assert String.contains?(payload, "type { name }")

        # > 25
        types = for i <- 1..26, do: %{"name" => "__T#{i}"}
        body = %{"data" => %{"__schema" => %{"types" => types}}}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{
            url: url,
            headers: [{"Content-Type", "application/json"}],
            payload: %{"query" => payload}
          }
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = CircularQueryIntrospection.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "Introspection-based Circular Query"
      assert res.severity == "HIGH"
      assert res.curl_verify == "curl ..."
      assert String.ends_with?(res.impact, "/graphql")
    end
  end

  test "returns result: true when types length > 25 (raw JSON string body fallback)" do
    types = for i <- 1..30, do: %{"name" => "__T#{i}"}
    decoded = %{"data" => %{"__schema" => %{"types" => types}}}
    json = Jason.encode!(decoded)

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          # simulate raw JSON string
          body: json,
          raw_body: json,
          request: %{url: url, headers: [], payload: %{"query" => "query cop {...}"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = CircularQueryIntrospection.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: false when types missing or <= 25" do
    # Case 1: types missing
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        body = %{"data" => %{"__schema" => %{}}}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = CircularQueryIntrospection.run(@url, @proxy, @headers, false)
      assert res.result == false
    end

    # Case 2: types present but length == 25
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        # threshold is > 25
        types = for i <- 1..25, do: %{"name" => "__T#{i}"}
        body = %{"data" => %{"__schema" => %{"types" => types}}}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = CircularQueryIntrospection.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: headers, payload: payload} ->
        send(parent, {:headers_seen, headers})
        # Return valid response with > 25 types so the check passes
        types = for i <- 1..26, do: %{"name" => "__T#{i}"}
        body = %{"data" => %{"__schema" => %{"types" => types}}}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = CircularQueryIntrospection.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert headers["X-GraphQL-Cop-Test"] == "Introspection-based Circular Query"
    end
  end
end
