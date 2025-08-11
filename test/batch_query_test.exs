defmodule GraphQLCop.Checks.BatchQueryTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.BatchQuery

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}

  test "returns result: true when response body is a list with >= 10 results" do
    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: _h, payload: payload, proxy: proxy} ->
        # Validate inputs (no pinning on module attributes)
        assert url == @url
        assert proxy == @proxy

        # Ensure we send an array payload with 10 operations
        assert is_list(payload)
        assert length(payload) == 10

        Enum.with_index(payload, 1)
        |> Enum.each(fn {op, i} ->
          assert op["operationName"] == "CopOp#{i}"
          assert op["query"] == "query CopOp#{i} { __typename }"
          assert op["variables"] == %{}
        end)

        # typical batched response
        body_list = for i <- 1..10, do: %{"data" => %{"__typename" => "__Schema#{i}"}}

        %{
          status: 200,
          body: body_list,
          raw_body: Jason.encode!(body_list),
          request: %{url: url, headers: [{"Content-Type", "application/json"}], payload: payload}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = BatchQuery.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "Array-based Query Batching"
      assert res.severity == "HIGH"
      assert res.curl_verify == "curl ..."
      assert String.ends_with?(res.impact, "/graphql")
    end
  end

  test "returns result: false when response body is not a list or has < 10 items" do
    # Case 1: not a list
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        %{
          status: 200,
          body: %{"data" => %{}},
          raw_body: ~s({"data":{}}),
          request: %{url: url, headers: [], payload: []}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = BatchQuery.run(@url, @proxy, @headers, false)
      assert res.result == false
    end

    # Case 2: list but under threshold
    with_mock GraphQLCop.Utils,
      graph_query: fn url, _opts ->
        list = for _ <- 1..5, do: %{"data" => %{"__typename" => "__Schema"}}

        %{
          status: 200,
          body: list,
          raw_body: Jason.encode!(list),
          request: %{url: url, headers: [], payload: []}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      res = BatchQuery.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{headers: headers, payload: payload} ->
        send(parent, {:headers_seen, headers})
        # Return a valid 10-item list so the check passes
        body_list = for _ <- 1..10, do: %{"data" => %{"__typename" => "__Schema"}}

        %{
          status: 200,
          body: body_list,
          raw_body: Jason.encode!(body_list),
          request: %{url: url, headers: [], payload: payload}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = BatchQuery.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert headers["X-GraphQL-Cop-Test"] == "Array-based Query Batching"
    end
  end

  test "payload is a list with exactly 10 operations (CopOp1..CopOp10)" do
    parent = self()

    with_mock GraphQLCop.Utils,
      graph_query: fn url, %{payload: payload} ->
        send(parent, {:payload_seen, payload})

        body_list = for _ <- 1..10, do: %{"data" => %{"__typename" => "__Schema"}}

        %{
          status: 200,
          body: body_list,
          raw_body: Jason.encode!(body_list),
          request: %{url: url, headers: [], payload: payload}
        }
      end,
      curlify: fn _ -> "curl ..." end do
      _ = BatchQuery.run(@url, @proxy, @headers, false)

      assert_receive {:payload_seen, payload}
      assert is_list(payload)
      assert length(payload) == 10

      # Validate shape and names
      Enum.with_index(payload, 1)
      |> Enum.each(fn {op, i} ->
        assert op["operationName"] == "CopOp#{i}"
        assert op["query"] == "query CopOp#{i} { __typename }"
        assert op["variables"] == %{}
      end)
    end
  end
end
