# test/graphql_cop/checks/post_based_csrf_test.exs
defmodule GraphQLCop.Checks.PostBasedCSRFTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.PostBasedCSRF

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}
  @q "query cop { __typename }"
  @encoded URI.encode_query(%{"query" => @q})

  test "returns result: true when server accepts urlencoded POST and returns data.__typename" do
    with_mock HTTPoison,
      post: fn url, body, headers, hackney: hackney_opts ->
        # call shape
        assert url == @url
        assert body == @encoded
        assert hackney_opts == []
        # headers normalized (list of tuples) and includes urlencoded content-type
        assert {"Content-Type", "application/x-www-form-urlencoded"} in headers
        assert {"Authorization", "Bearer test"} in headers

        resp_body = %{"data" => %{"__typename" => "__Schema"}}
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(resp_body)}}
      end do
      res = PostBasedCSRF.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "POST based url-encoded query (possible CSRF)"
      assert res.description == "GraphQL accepts non-JSON queries over POST"
      assert res.severity == "MEDIUM"
      assert res.color == "yellow"
      assert String.ends_with?(res.impact, "/graphql")
      assert String.starts_with?(res.curl_verify, "curl -s -X POST ")
      assert String.contains?(res.curl_verify, @url)
      assert String.contains?(res.curl_verify, @encoded)
    end
  end

  test "returns result: false when response lacks data.__typename" do
    with_mock HTTPoison,
      post: fn _url, _body, _headers, hackney: _opts ->
        resp_body = %{"errors" => [%{"message" => "Unsupported content type"}]}
        {:ok, %HTTPoison.Response{status_code: 400, body: Jason.encode!(resp_body)}}
      end do
      res = PostBasedCSRF.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds debug header when debug_mode is true" do
    parent = self()

    with_mock HTTPoison,
      post: fn _url, body, headers, hackney: _opts ->
        send(parent, {:seen_headers, headers})
        assert body == @encoded

        resp_body = %{"data" => %{"__typename" => "__Schema"}}
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(resp_body)}}
      end do
      _ = PostBasedCSRF.run(@url, @proxy, @headers, true)

      assert_receive {:seen_headers, headers}
      assert {"X-GraphQL-Cop-Test", "POST based url-encoded query (possible CSRF)"} in headers
      assert {"Content-Type", "application/x-www-form-urlencoded"} in headers
    end
  end

  test "passes through proxy when provided" do
    proxy = "http://127.0.0.1:8080"

    with_mock HTTPoison,
      post: fn _url, body, _headers, hackney: opts ->
        assert body == @encoded
        assert Keyword.get(opts, :proxy) == proxy

        resp_body = %{"data" => %{"__typename" => "__Schema"}}
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(resp_body)}}
      end do
      res = PostBasedCSRF.run(@url, proxy, @headers, false)
      assert res.result == true
    end
  end

  test "handles HTTPoison error tuple gracefully (result: false, curl built)" do
    with_mock HTTPoison,
      post: fn _url, _body, _headers, hackney: _opts ->
        {:error, %HTTPoison.Error{id: nil, reason: :timeout}}
      end do
      res = PostBasedCSRF.run(@url, @proxy, @headers, false)
      assert res.result == false
      assert String.starts_with?(res.curl_verify, "curl -s -X POST ")
    end
  end
end
