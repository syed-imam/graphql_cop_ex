# test/graphql_cop/checks/get_method_support_test.exs
defmodule GraphQLCop.Checks.GetMethodSupportTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.GetMethodSupport

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}
  @query "query cop { __typename }"

  defp parse_query(url) do
    %URI{query: qs} = URI.parse(url)
    URI.decode_query(qs || "")
  end

  test "returns result: true when query executes over GET (data.__typename present)" do
    with_mock HTTPoison,
      get: fn url, headers, hackney: hackney_opts ->
        # proxy passthrough
        assert hackney_opts == []
        # headers normalized (list of tuples)
        assert {"Authorization", "Bearer test"} in headers

        # URL includes our query param (decoded)
        params = parse_query(url)
        assert params["query"] == @query

        body = %{"data" => %{"__typename" => "__Schema"}}
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}}
      end do
      res = GetMethodSupport.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "GET Method Query Support"
      assert res.description == "GraphQL queries allowed using the GET method"
      assert res.severity == "MEDIUM"
      assert String.ends_with?(res.impact, "/graphql")
      assert String.starts_with?(res.curl_verify, "curl -s -X GET ")
      assert String.contains?(res.curl_verify, @url)
    end
  end

  test "returns result: false when response lacks data.__typename" do
    with_mock HTTPoison,
      get: fn _url, _headers, hackney: _opts ->
        body = %{"errors" => [%{"message" => "GET not allowed for queries"}]}
        {:ok, %HTTPoison.Response{status_code: 400, body: Jason.encode!(body)}}
      end do
      res = GetMethodSupport.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock HTTPoison,
      get: fn url, headers, hackney: _opts ->
        send(parent, {:headers_seen, headers})

        params = parse_query(url)
        assert params["query"] == @query

        body = %{"data" => %{"__typename" => "__Schema"}}
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}}
      end do
      _ = GetMethodSupport.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert {"X-GraphQL-Cop-Test", "GET Method Query Support"} in headers
    end
  end

  test "handles HTTPoison error tuple gracefully (result: false, curl still built)" do
    with_mock HTTPoison,
      get: fn _url, _headers, hackney: _opts ->
        {:error, %HTTPoison.Error{id: nil, reason: :econnrefused}}
      end do
      res = GetMethodSupport.run(@url, @proxy, @headers, false)
      assert res.result == false
      assert String.starts_with?(res.curl_verify, "curl -s -X GET ")
    end
  end

  test "passes through proxy when provided" do
    proxy = "http://127.0.0.1:8080"

    with_mock HTTPoison,
      get: fn _url, _headers, hackney: opts ->
        # ensure proxy added to hackney options
        assert Keyword.get(opts, :proxy) == proxy

        body = %{"data" => %{"__typename" => "__Schema"}}
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}}
      end do
      res = GetMethodSupport.run(@url, proxy, @headers, false)
      assert res.result == true
    end
  end
end
