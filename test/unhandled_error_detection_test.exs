# test/graphql_cop/checks/unhandled_error_detection_test.exs
defmodule GraphQLCop.Checks.UnhandledErrorDetectionTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.UnhandledErrorDetection

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}
  @bad_query "qwerty cop { abc }"

  test "returns result: true when errors[0].extensions.exception present (decoded map body)" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: _h, payload: payload, proxy: proxy} ->
        assert url == @url
        assert proxy == @proxy
        assert is_binary(payload)
        assert String.contains?(payload, "qwerty cop")
        assert String.contains?(payload, "abc")

        body = %{
          "errors" => [
            %{
              "message" => "boom",
              "extensions" => %{"exception" => %{"stacktrace" => ["..."]}}
            }
          ]
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
      res = UnhandledErrorDetection.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "Unhandled Errors Detection"
      assert res.description == "Exception errors are not handled"
      assert res.severity == "INFO"
      assert res.color == "green"
      assert String.ends_with?(res.impact, "/graphql")
      assert res.curl_verify == "curl ..."
    end
  end

  test "returns result: true when body is raw JSON string containing extensions.exception" do
    decoded = %{
      "errors" => [
        %{"extensions" => %{"exception" => %{"message" => "kaboom"}}}
      ]
    }

    json = Jason.encode!(decoded)

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          # raw JSON string
          body: json,
          raw_body: json,
          request: %{url: url, headers: [], payload: %{"query" => @bad_query}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = UnhandledErrorDetection.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: true via non-JSON fallback when body contains \"extensions\" and \"exception\"" do
    body = ~s(random text ... "extensions": {"exception": {"code":"E_FAIL"}} ...)

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          # not JSON; should hit substring fallback
          body: body,
          raw_body: body,
          request: %{url: url, headers: [], payload: %{"query" => @bad_query}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = UnhandledErrorDetection.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: false when no exception info is present" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        body = %{"errors" => [%{"message" => "Invalid query"}]}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => @bad_query}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = UnhandledErrorDetection.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: headers, payload: payload} ->
        send(parent, {:headers_seen, headers})
        assert payload == @bad_query

        body = %{"errors" => [%{"extensions" => %{"exception" => %{}}}]}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = UnhandledErrorDetection.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert headers["X-GraphQL-Cop-Test"] == "Unhandled Errors Detection"
    end
  end
end
