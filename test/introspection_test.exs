defmodule GraphQLCop.Checks.IntrospectionTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.Introspection

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}

  test "returns result: true when __schema.types is non-empty (decoded map body)" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: _h, payload: payload, proxy: proxy} ->
        # Validate inputs
        assert url == @url
        assert proxy == @proxy
        assert is_binary(payload)
        assert String.contains?(payload, "__schema")
        assert String.contains?(payload, "types")
        assert String.contains?(payload, "fields { name }")

        body = %{
          "data" => %{
            "__schema" => %{"types" => [%{"name" => "Query", "fields" => [%{"name" => "hello"}]}]}
          }
        }

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
      res = Introspection.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "Introspection"
      assert res.description == "Introspection Query Enabled"
      assert res.severity == "HIGH"
      assert res.color == "red"
      assert String.ends_with?(res.impact, "/graphql")
      assert res.curl_verify == "curl ..."
    end
  end

  test "returns result: true when body is raw JSON string with non-empty types" do
    decoded = %{
      "data" => %{
        "__schema" => %{"types" => [%{"name" => "Query", "fields" => [%{"name" => "hello"}]}]}
      }
    }

    json = Jason.encode!(decoded)

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          # raw JSON body (string)
          body: json,
          raw_body: json,
          request: %{url: url, headers: [], payload: %{"query" => "query cop {...}"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = Introspection.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: false when types missing or empty" do
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
      res = Introspection.run(@url, @proxy, @headers, false)
      assert res.result == false
    end

    # Case 2: types present but empty list
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        body = %{"data" => %{"__schema" => %{"types" => []}}}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = Introspection.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: headers, payload: payload} ->
        send(parent, {:headers_seen, headers})

        body = %{
          "data" => %{
            "__schema" => %{"types" => [%{"name" => "Query", "fields" => [%{"name" => "hello"}]}]}
          }
        }

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = Introspection.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert headers["X-GraphQL-Cop-Test"] == "Introspection"
    end
  end
end
