defmodule GraphQLCop.Checks.TraceModeTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.TraceMode

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}
  @q "query cop { __typename }"

  test "returns result: true when errors[0].extensions.tracing is present (decoded map body)" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: _h, payload: payload, proxy: proxy} ->
        assert url == @url
        assert proxy == @proxy
        assert is_binary(payload)
        assert String.contains?(payload, "__typename")

        body = %{
          "data" => %{"__typename" => "__Schema"},
          "errors" => [
            %{"message" => "example", "extensions" => %{"tracing" => %{"version" => 1}}}
          ]
        }

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = TraceMode.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "Trace Mode"
      assert res.description == "Tracing is Enabled"
      assert res.severity == "INFO"
      assert res.color == "green"
      assert String.ends_with?(res.impact, "/graphql")
      assert res.curl_verify == "curl ..."
    end
  end

  test "returns result: true when top-level extensions.tracing is present (decoded map body)" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        body = %{
          "data" => %{"__typename" => "__Schema"},
          "extensions" => %{"tracing" => %{"duration" => 123}}
        }

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => @q}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = TraceMode.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: true when body is raw JSON string containing tracing" do
    decoded = %{
      "data" => %{"__typename" => "__Schema"},
      "errors" => [%{"extensions" => %{"tracing" => %{"foo" => "bar"}}}]
    }

    json = Jason.encode!(decoded)

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          # raw JSON string
          body: json,
          raw_body: json,
          request: %{url: url, headers: [], payload: %{"query" => @q}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = TraceMode.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: true via non-JSON string fallback ('\"extensions\"' and '\"tracing\"' substrings)" do
    # Not valid JSON on purpose; should hit the binary fallback path
    body = ~s(some error ... "extensions": {"tracing": {"x": 1}} ...)

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          # non-JSON string
          body: body,
          raw_body: body,
          request: %{url: url, headers: [], payload: %{"query" => @q}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = TraceMode.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: false when no tracing info is present" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        body = %{"data" => %{"__typename" => "__Schema"}}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => @q}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = TraceMode.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: headers, payload: payload} ->
        send(parent, {:headers_seen, headers})
        assert String.contains?(payload, "__typename")

        body = %{
          "errors" => [%{"extensions" => %{"tracing" => %{}}}],
          "data" => %{"__typename" => "__Schema"}
        }

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = TraceMode.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert headers["X-GraphQL-Cop-Test"] == "Trace Mode"
    end
  end
end
