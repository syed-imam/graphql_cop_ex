defmodule GraphQLCop.Checks.DetectGraphiQLTest do
  use ExUnit.Case, async: false
  import Mock

  alias GraphQLCop.Checks.DetectGraphiQL

  @url "https://example.com/graphql"
  @proxy nil
  @headers %{"Authorization" => "Bearer test"}

  test "returns result: true when response body contains GraphiQL/Playground markers" do
    with_mock HTTPoison,
      get: fn url, headers, hackney: opts ->
        assert url == @url
        assert opts == []
        # headers are normalized list of tuples and include Accept: text/html
        assert {"Authorization", "Bearer test"} in headers
        assert {"Accept", "text/html"} in headers

        html = """
        <html>
          <head><link rel="stylesheet" href="graphiql.min.css"></head>
          <body>GraphiQL</body>
        </html>
        """

        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end do
      res = DetectGraphiQL.run(@url, @proxy, @headers, false)

      assert res.result == true
      assert res.title == "GraphQL IDE"
      assert res.description == "GraphiQL Explorer/Playground Enabled"
      assert res.severity == "LOW"
      assert res.color == "blue"
      assert String.ends_with?(res.impact, "/graphql")
      assert String.starts_with?(res.curl_verify, "curl -s -X GET ")
      assert String.contains?(res.curl_verify, @url)
    end
  end

  test "returns result: false when response body has no known markers" do
    with_mock HTTPoison,
      get: fn _url, _headers, hackney: _opts ->
        html = "<html><body>No IDE here</body></html>"
        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end do
      res = DetectGraphiQL.run(@url, @proxy, @headers, false)
      assert res.result == false
    end
  end

  test "adds Accept: text/html and debug header when debug_mode is true" do
    parent = self()

    with_mock HTTPoison,
      get: fn _url, headers, hackney: _opts ->
        send(parent, {:headers_seen, headers})
        html = "<html><body>GraphQL Playground</body></html>"
        {:ok, %HTTPoison.Response{status_code: 200, body: html}}
      end do
      _ = DetectGraphiQL.run(@url, @proxy, @headers, true)

      assert_receive {:headers_seen, headers}
      assert {"Accept", "text/html"} in headers
      assert {"X-GraphQL-Cop-Test", "GraphQL IDE"} in headers
    end
  end

  test "passes through proxy when provided" do
    proxy = "http://127.0.0.1:8080"

    with_mock HTTPoison,
      get: fn _url, _headers, hackney: opts ->
        assert Keyword.get(opts, :proxy) == proxy
        {:ok, %HTTPoison.Response{status_code: 200, body: "GraphQL Playground"}}
      end do
      res = DetectGraphiQL.run(@url, proxy, @headers, false)
      assert res.result == true
    end
  end

  test "handles HTTPoison error tuple gracefully (result false, curl built)" do
    with_mock HTTPoison,
      get: fn _url, _headers, hackney: _opts ->
        {:error, %HTTPoison.Error{id: nil, reason: :econnrefused}}
      end do
      res = DetectGraphiQL.run(@url, @proxy, @headers, false)
      assert res.result == false
      assert String.starts_with?(res.curl_verify, "curl -s -X GET ")
    end
  end
end
