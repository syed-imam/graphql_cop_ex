defmodule GraphQLCop.Checks.FieldDuplicationTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.FieldDuplication

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}

  test "returns result: true when data.__typename is present (decoded map body)" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: _h, payload: payload, proxy: proxy} ->
        # Validate inputs
        assert url == @url
        assert proxy == @proxy
        assert is_binary(payload)
        assert String.starts_with?(String.trim_leading(payload), "query cop {")
        # Ensure we repeated __typename many times
        occur =
          payload
          |> String.split("\n")
          |> Enum.count(&String.contains?(&1, "__typename"))

        assert occur >= 500

        body = %{"data" => %{"__typename" => "__Schema"}}

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
      res = FieldDuplication.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "Field Duplication"
      assert res.severity == "HIGH"
      assert res.curl_verify == "curl ..."
      assert String.ends_with?(res.impact, "/graphql")
    end
  end

  test "returns result: true when body is raw JSON string with data.__typename" do
    decoded = %{"data" => %{"__typename" => "__Schema"}}
    json = Jason.encode!(decoded)

    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          # raw JSON (exercise fallback decode)
          body: json,
          raw_body: json,
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = FieldDuplication.run(@url, @proxy, @headers, false)
      assert res.result == true
    end
  end

  test "returns result: false when __typename missing" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        body = %{"data" => %{"something_else" => "ok"}}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => "q"}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = FieldDuplication.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: headers, payload: payload} ->
        send(parent, {:headers_seen, headers})

        body = %{"data" => %{"__typename" => "__Schema"}}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = FieldDuplication.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert headers["X-GraphQL-Cop-Test"] == "Field Duplication"
    end
  end

  test "payload contains exactly 500 duplicated __typename lines (allowing whitespace variance)" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{payload: payload} ->
        send(parent, {:payload_seen, payload})

        body = %{"data" => %{"__typename" => "__Schema"}}

        %{
          status: 200,
          body: body,
          raw_body: Jason.encode!(body),
          request: %{url: url, headers: [], payload: %{"query" => payload}}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = FieldDuplication.run(@url, @proxy, @headers, false)

      assert_receive {:payload_seen, payload}
      # Count occurrences irrespective of trailing spaces
      count =
        Regex.scan(~r/__typename\b/, payload)
        |> length()

      assert count == 500
    end
  end
end
