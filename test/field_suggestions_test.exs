defmodule GraphQLCop.Checks.FieldSuggestionsTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.FieldSuggestions

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}

  test "returns result: true when an error contains 'Did you mean' (decoded map body)" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: _h, payload: payload, proxy: proxy} ->
        # Validate call shape
        assert url == @url
        assert proxy == @proxy
        assert is_binary(payload)
        assert String.contains?(payload, "__schema")
        assert String.contains?(payload, "{ directive }")

        errors = [
          %{
            "message" =>
              "Cannot query field 'directive' on type '__Schema'. Did you mean 'directives'?"
          }
        ]

        body = %{"errors" => errors}

        %{
          status: 400,
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
      res = FieldSuggestions.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "Field Suggestions"
      assert res.description == "Field Suggestions are Enabled"
      assert res.severity == "LOW"
      assert res.color == "blue"
      assert res.curl_verify == "curl ..."
      assert String.ends_with?(res.impact, "/graphql")
    end
  end

  test "returns result: true when an error contains 'Did you mean' (raw JSON string body)" do
    errors = [
      %{"message" => "Unknown field 'directive'. Did you mean 'directives'?"}
    ]

    json = Jason.encode!(%{"errors" => errors})

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 400,
          # raw JSON string to exercise fallback decoding
          body: json,
          raw_body: json,
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = FieldSuggestions.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: false when errors missing or message lacks suggestion text" do
    # Case 1: no errors key
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
      res = FieldSuggestions.run(@url, @proxy, @headers, false)
      assert res.result == false
    end

    # Case 2: errors present but no "Did you mean"
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        errors = [%{"message" => "Cannot query field 'directive' on type '__Schema'."}]
        body = %{"errors" => errors}

        %{
          status: 400,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = FieldSuggestions.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: headers, payload: payload} ->
        send(parent, {:headers_seen, headers})

        errors = [
          %{"message" => "Cannot query field 'directive'. Did you mean 'directives'?"}
        ]

        body = %{"errors" => errors}

        %{
          status: 400,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = FieldSuggestions.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert headers["X-GraphQL-Cop-Test"] == "Field Suggestions"
    end
  end
end
