defmodule GraphQLCop.Checks.AliasOverloadingTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.AliasOverloading

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}

  test "returns result: true when alias100 present (decoded map body)" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: _h, payload: payload, proxy: proxy} ->
        # validate inputs (no pinning on module attributes)
        assert url == @url
        assert proxy == @proxy
        assert is_binary(payload)
        assert String.contains?(payload, "alias100: __typename")

        %{
          status: 200,
          body: %{"data" => %{"alias100" => "__Schema"}},
          raw_body: ~s({"data":{"alias100":"__Schema"}}),
          request: %{
            url: url,
            headers: [{"Content-Type", "application/json"}],
            payload: %{"query" => payload}
          }
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = AliasOverloading.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "Alias Overloading"
      assert res.severity == "HIGH"
      assert res.curl_verify == "curl ..."
      assert String.ends_with?(res.impact, "/graphql")
    end
  end

  test "returns result: true when alias100 present (raw JSON string body - fallback decode path)" do
    json = ~s({"data":{"alias100":"__Schema"}})

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          # simulate raw string body
          body: json,
          raw_body: json,
          request: %{url: url, headers: [], payload: %{"query" => "query cop {...}"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = AliasOverloading.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: false when alias100 is missing" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          body: %{"data" => %{"alias0" => "__Schema"}},
          raw_body: ~s({"data":{"alias0":"__Schema"}}),
          request: %{url: url, headers: [], payload: %{"query" => "query cop {...}"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = AliasOverloading.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: headers} = _opts ->
        send(parent, {:headers_seen, headers})

        %{
          status: 200,
          body: %{"data" => %{"alias100" => "__Schema"}},
          raw_body: ~s({"data":{"alias100":"__Schema"}}),
          request: %{url: url, headers: [], payload: %{"query" => "query cop {...}"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = AliasOverloading.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert headers["X-GraphQL-Cop-Test"] == "Alias Overloading"
    end
  end

  test "builds 101 aliases including alias0..alias100" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{payload: payload} = _opts ->
        send(parent, {:payload_seen, payload})

        %{
          status: 200,
          body: %{"data" => %{"alias100" => "__Schema"}},
          raw_body: ~s({"data":{"alias100":"__Schema"}}),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = AliasOverloading.run(@url, @proxy, @headers, false)

      assert_receive {:payload_seen, payload}
      assert String.starts_with?(String.trim_leading(payload), "query cop {")
      assert String.contains?(payload, "alias0: __typename")
      assert String.contains?(payload, "alias100: __typename")

      alias_count =
        payload
        |> String.split("\n")
        |> Enum.count(&String.contains?(&1, ": __typename"))

      assert alias_count == 101
    end
  end
end
