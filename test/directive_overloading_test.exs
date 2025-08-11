defmodule GraphQLCop.Checks.DirectiveOverloadingTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.DirectiveOverloading

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}

  test "returns result: true when errors length is exactly 10 (decoded map body)" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: _h, payload: payload, proxy: proxy} ->
        assert url == @url
        assert proxy == @proxy
        assert is_binary(payload)
        # make sure our payload has the duplicated directives
        assert String.contains?(payload, "__typename")
        assert String.contains?(payload, "@aa@aa@aa@aa@aa@aa@aa@aa@aa@aa")

        errors = for i <- 1..10, do: %{"message" => "Bad directive #{i}"}

        %{
          status: 200,
          body: %{"errors" => errors},
          raw_body: Jason.encode!(%{"errors" => errors}),
          request: %{
            url: url,
            headers: [{"Content-Type", "application/json"}],
            payload: %{"query" => payload}
          }
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = DirectiveOverloading.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "Directive Overloading"
      assert res.severity == "HIGH"
      assert res.curl_verify == "curl ..."
      assert String.ends_with?(res.impact, "/graphql")
    end
  end

  test "returns result: true when errors length is exactly 10 (raw JSON body fallback)" do
    errors = for i <- 1..10, do: %{"message" => "Bad directive #{i}"}
    json = Jason.encode!(%{"errors" => errors})

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          # raw JSON string body
          body: json,
          raw_body: json,
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = DirectiveOverloading.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: false when errors missing or count != 10" do
    # Case 1: no errors key
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          body: %{"data" => %{"__typename" => "__Schema"}},
          raw_body: ~s({"data":{"__typename":"__Schema"}}),
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = DirectiveOverloading.run(@url, @proxy, @headers, false)
      assert res.result == false
    end

    # Case 2: errors but not 10
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        errors = for i <- 1..3, do: %{"message" => "Bad directive #{i}"}

        %{
          status: 200,
          body: %{"errors" => errors},
          raw_body: Jason.encode!(%{"errors" => errors}),
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = DirectiveOverloading.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: headers, payload: payload} ->
        send(parent, {:headers_seen, headers})

        errors = for i <- 1..10, do: %{"message" => "Bad directive #{i}"}

        %{
          status: 200,
          body: %{"errors" => errors},
          raw_body: Jason.encode!(%{"errors" => errors}),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = DirectiveOverloading.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert headers["X-GraphQL-Cop-Test"] == "Directive Overloading"
    end
  end
end
