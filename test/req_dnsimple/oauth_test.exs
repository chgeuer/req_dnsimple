defmodule ReqDnsimple.OAuthTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @token_data %{
    "access_token" => "fake-offline-access-token",
    "token_type" => "Bearer",
    "scope" => nil,
    "account_id" => 1010
  }

  describe "authorize_url/2 and authorize_url/3" do
    test "builds the production authorization URL without optional parameters" do
      assert {:ok,
              "https://app.dnsimple.com/oauth/authorize?response_type=code&client_id=offline-client"} =
               ReqDnsimple.OAuth.authorize_url(authorize_client(), "offline-client")

      refute_received {:request, _request}
    end

    test "maps the production host case-insensitively and discards API URL suffixes" do
      for origin <- [
            "https://api.dnsimple.com",
            "https://api.dnsimple.com/",
            "https://api.dnsimple.com/v2/",
            "https://api.dnsimple.com/gateway/v2/domains?state=ignored#ignored",
            "HTTPS://API.DNSIMPLE.COM/v2",
            "https://aPi.DnSiMpLe.CoM/v2"
          ] do
        assert {:ok,
                "https://app.dnsimple.com/oauth/authorize?response_type=code&client_id=offline-client"} =
                 ReqDnsimple.OAuth.authorize_url(authorize_client(origin), "offline-client")
      end

      refute_received {:request, _request}
    end

    test "uses the sandbox website instead of production" do
      for origin <- [
            "https://api.sandbox.dnsimple.com/v2",
            "https://api.sandbox.dnsimple.com/v2/?page=2#ignored"
          ] do
        assert {:ok,
                "https://sandbox.dnsimple.com/oauth/authorize?response_type=code&client_id=offline-client"} =
                 ReqDnsimple.OAuth.authorize_url(authorize_client(origin), "offline-client")
      end

      refute_received {:request, _request}
    end

    test "preserves custom schemes and ports and only removes a leading api hostname label" do
      for {origin, website} <- [
            {"https://api.dnsimple.test/v2", "https://dnsimple.test"},
            {"https://api.dnsimple.com.test/v2", "https://dnsimple.com.test"},
            {"http://api.dnsimple.test:4001/gateway/v2/", "http://dnsimple.test:4001"},
            {"https://proxy.api.dnsimple.test:8443/v2", "https://proxy.api.dnsimple.test:8443"},
            {"http://localhost:4001/v2", "http://localhost:4001"},
            {"http://127.0.0.1:4001/v2", "http://127.0.0.1:4001"},
            {"http://[::1]:4001/v2", "http://[::1]:4001"}
          ] do
        assert {:ok, url} =
                 ReqDnsimple.OAuth.authorize_url(authorize_client(origin), "offline-client")

        assert url == website <> "/oauth/authorize?response_type=code&client_id=offline-client"
      end

      refute_received {:request, _request}
    end

    test "accepts static URI base URLs as well as strings" do
      for origin <- [
            URI.new!("https://api.dnsimple.test:8443/v2/?state=ignored#ignored"),
            %URI{scheme: "https", host: "api.dnsimple.test", port: 8443, path: "/v2"}
          ] do
        assert {:ok,
                "https://dnsimple.test:8443/oauth/authorize?response_type=code&client_id=offline-client"} =
                 ReqDnsimple.OAuth.authorize_url(authorize_client(origin), "offline-client")
      end

      refute_received {:request, _request}
    end

    test "URI encodes client ID, redirect URI, and state without changing their values" do
      client_id = "client &+/?=ä"
      redirect_uri = "http://127.0.0.1:54321/callback?next=/a+b&label=hello world#return"
      state = "random &+/?=# % ü"

      assert {:ok, url} =
               ReqDnsimple.OAuth.authorize_url(authorize_client(), client_id,
                 redirect_uri: redirect_uri,
                 state: state
               )

      uri = URI.new!(url)
      assert uri.host == "app.dnsimple.com"
      assert uri.path == "/oauth/authorize"
      assert uri.fragment == nil

      assert URI.decode_query(uri.query) == %{
               "response_type" => "code",
               "client_id" => client_id,
               "redirect_uri" => redirect_uri,
               "state" => state
             }

      assert url =~ "%26"
      assert url =~ "%2B"
      assert url =~ "%23"
      refute_received {:request, _request}
    end

    test "preserves explicitly empty optional strings and an explicit account selector" do
      assert {:ok, url} =
               ReqDnsimple.OAuth.authorize_url(authorize_client(), "offline-client",
                 state: "",
                 redirect_uri: "",
                 account_id: 0
               )

      assert URI.decode_query(URI.new!(url).query) == %{
               "response_type" => "code",
               "client_id" => "offline-client",
               "state" => "",
               "redirect_uri" => "",
               "account_id" => "0"
             }

      refute_received {:request, _request}
    end

    test "supports an S256 challenge without exposing the verifier in the browser URL" do
      verifier = String.duplicate("a", 43)
      challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

      assert {:ok, url} =
               ReqDnsimple.OAuth.authorize_url(authorize_client(), "offline-client",
                 code_challenge: challenge,
                 code_challenge_method: "S256",
                 state: "offline-state"
               )

      assert URI.decode_query(URI.new!(url).query) == %{
               "response_type" => "code",
               "client_id" => "offline-client",
               "state" => "offline-state",
               "code_challenge" => challenge,
               "code_challenge_method" => "S256"
             }

      refute url =~ verifier
      refute url =~ "code_verifier"
      refute_received {:request, _request}
    end

    test "is independent of account scope, authentication, request steps, and HTTP" do
      test_pid = self()

      request =
        ReqDnsimple.new_unscoped_client(
          fn ->
            send(test_pid, :auth_callback_evaluated)
            "must-not-be-used"
          end,
          adapter: fn _request -> flunk("authorization URL construction must not send HTTP") end
        )
        |> Req.Request.put_header("authorization", "Basic must-not-be-used")
        |> Req.Request.prepend_request_steps(
          forbid_request: fn _request ->
            flunk("authorization URL construction must not run steps")
          end
        )

      for current <- [
            request,
            ReqDnsimple.for_account(request, 1010),
            ReqDnsimple.for_account(request, 2020)
          ] do
        original = current

        assert {:ok, url} = ReqDnsimple.OAuth.authorize_url(current, "offline-client")
        refute Map.has_key?(URI.decode_query(URI.new!(url).query), "account_id")

        assert {:ok, selected_url} =
                 ReqDnsimple.OAuth.authorize_url(current, "offline-client", account_id: 3030)

        assert URI.decode_query(URI.new!(selected_url).query)["account_id"] == "3030"
        assert current == original
      end

      assert Req.Request.get_header(request, "authorization") == ["Basic must-not-be-used"]
      refute_received :auth_callback_evaluated
    end

    test "rejects invalid clients and client IDs explicitly" do
      for request <- [nil, false, 0, [], %{}, "not a request"] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.OAuth.authorize_url(request, "offline-client")
      end

      for client_id <- [nil, false, 0, :client, [], %{}, ""] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.OAuth.authorize_url(authorize_client(), client_id)
      end

      refute_received {:request, _request}
    end

    test "rejects illegal option containers, duplicates, fields, and values" do
      for opts <- [
            nil,
            false,
            "options",
            %{},
            [:invalid],
            [{:state}],
            [{"state", "value"}],
            [{:state, "value"} | :invalid],
            [state: "one", state: "two"],
            [state: nil],
            [state: false],
            [redirect_uri: nil],
            [redirect_uri: 0],
            [account_id: nil],
            [account_id: -1],
            [account_id: "1010"],
            [response_type: "token"],
            [client_id: "replacement"],
            [client_secret: "must-not-leak"],
            [code_verifier: String.duplicate("a", 43)],
            [scope: "unused"],
            [unknown: true]
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.OAuth.authorize_url(authorize_client(), "offline-client", opts)
      end

      refute_received {:request, _request}
    end

    test "requires a well-formed S256 challenge and method together" do
      challenge = String.duplicate("a", 43)

      for opts <- [
            [code_challenge: challenge],
            [code_challenge_method: "S256"],
            [code_challenge: challenge, code_challenge_method: "plain"],
            [code_challenge: challenge, code_challenge_method: nil],
            [code_challenge: nil, code_challenge_method: "S256"],
            [code_challenge: false, code_challenge_method: "S256"],
            [code_challenge: "", code_challenge_method: "S256"],
            [code_challenge: String.duplicate("a", 42), code_challenge_method: "S256"],
            [code_challenge: String.duplicate("a", 44), code_challenge_method: "S256"],
            [code_challenge: String.duplicate("a", 42) <> "+", code_challenge_method: "S256"],
            [code_challenge: String.duplicate("a", 42) <> "=", code_challenge_method: "S256"]
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.OAuth.authorize_url(authorize_client(), "offline-client", opts)
      end

      refute_received {:request, _request}
    end

    test "rejects missing, malformed, unsupported, and credential-bearing origins" do
      for origin <- [
            nil,
            false,
            123,
            "",
            "/v2",
            "api.dnsimple.com/v2",
            "//api.dnsimple.com/v2",
            "https://",
            "https:///v2",
            "ftp://api.dnsimple.com/v2",
            "https://user:password@api.dnsimple.com/v2",
            "https://bad host/v2",
            "https://api./v2",
            "https://api..dnsimple.test/v2",
            "https://api.dnsimple.test:bad/v2",
            "https://api.dnsimple.test:0/v2",
            "https://api.dnsimple.test:65536/v2",
            %URI{scheme: "https", host: "api.dnsimple.test", port: "bad"},
            %URI{scheme: "https", host: nil},
            %URI{scheme: "https", host: "bad host"},
            {URI, :parse, ["https://api.dnsimple.com/v2"]}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.OAuth.authorize_url(authorize_client(origin), "offline-client")
      end

      refute_received {:request, _request}
    end

    test "does not evaluate a dynamic base URL or silently fall back to production" do
      test_pid = self()

      origin = fn ->
        send(test_pid, :base_url_callback_evaluated)
        "https://api.dnsimple.com/v2"
      end

      assert {:error, %NimbleOptions.ValidationError{}} =
               ReqDnsimple.OAuth.authorize_url(authorize_client(origin), "offline-client")

      request = authorize_client() |> Req.Request.delete_option(:base_url)

      assert {:error, %NimbleOptions.ValidationError{}} =
               ReqDnsimple.OAuth.authorize_url(request, "offline-client")

      refute_received :base_url_callback_evaluated
      refute_received {:request, _request}
    end
  end

  describe "exchange_code/2" do
    test "token exchange returns HTTP metadata and preserves malformed-header diagnostics" do
      attrs = [
        client_id: "offline-client",
        client_secret: "offline-secret",
        code: "offline-code",
        grant_type: "authorization_code"
      ]

      headers = [
        {"x-ratelimit-remaining", "0"},
        {"x-request-id", "oauth-response"},
        {"retry-after", "120"}
      ]

      assert {:ok,
              {%ReqDnsimple.OAuth.Token{account_id: 1010},
               %ReqDnsimple.Metadata{
                 status: 200,
                 rate_limit_remaining: 0,
                 request_id: "oauth-response"
               }}} =
               ReqDnsimple.OAuth.exchange_code(client(200, @token_data, self(), headers), attrs)

      assert_request(:post, "/v2/oauth/access_token", %{}, Map.new(attrs))

      assert {:error,
              %ReqDnsimple.Error{
                reason: reason,
                metadata: %ReqDnsimple.Metadata{
                  status: 429,
                  rate_limit_remaining: 0,
                  request_id: "oauth-response",
                  retry_after: "120"
                }
              }} =
               ReqDnsimple.OAuth.exchange_code(
                 client(429, %{"message" => "rate limited"}, self(), headers),
                 attrs
               )

      assert reason.status == 429
      refute Map.has_key?(reason, :retry_after)
      assert_request(:post, "/v2/oauth/access_token", %{}, Map.new(attrs))

      assert {:ok,
              {%ReqDnsimple.OAuth.Token{account_id: 1010},
               %ReqDnsimple.Metadata{
                 status: 200,
                 rate_limit_remaining: nil,
                 parse_errors: %{rate_limit_remaining: {:invalid_header, ["invalid"]}}
               }}} =
               ReqDnsimple.OAuth.exchange_code(
                 client(200, @token_data, self(), [{"x-ratelimit-remaining", "invalid"}]),
                 attrs
               )

      assert_request(:post, "/v2/oauth/access_token", %{}, Map.new(attrs))
      refute_received {:request, _request}
    end

    test "oauthToken exchanges a public-client PKCE code without inherited authentication" do
      test_pid = self()

      request =
        ReqDnsimple.new_client(fn ->
          send(test_pid, :auth_callback_evaluated)
          "must-not-be-used"
        end)
        |> Req.Request.put_header("authorization", "Basic must-not-be-used")
        |> Req.merge(
          adapter: fn request ->
            send(test_pid, {:oauth_request, request})
            {request, %Req.Response{status: 200, body: @token_data}}
          end,
          retry: false
        )

      attrs = [
        client_id: "fake-offline-client",
        code: "fake-offline-code",
        grant_type: "authorization_code",
        code_verifier: String.duplicate("a", 43),
        redirect_uri: "http://127.0.0.1:54321/callback",
        state: "fake-offline-state"
      ]

      assert {:ok,
              {%ReqDnsimple.OAuth.Token{
                 access_token: "fake-offline-access-token",
                 token_type: "Bearer",
                 scope: nil,
                 account_id: 1010
               }, %ReqDnsimple.Metadata{}}} = ReqDnsimple.OAuth.exchange_code(request, attrs)

      assert_receive {:oauth_request, sent_request}
      assert sent_request.method == :post
      assert sent_request.url.path == "/v2/oauth/access_token"
      assert sent_request.url.query == nil
      assert Req.Request.get_header(sent_request, "authorization") == []

      assert Jason.decode!(sent_request.body) ==
               Map.new(attrs, fn {key, value} ->
                 {to_string(key), value}
               end)

      refute_received :auth_callback_evaluated
      refute_received {:oauth_request, _request}
    end

    test "oauthToken exchanges a confidential-client code with omitted optional fields" do
      attrs = [
        client_id: "fake-offline-client",
        client_secret: "fake-offline-secret",
        code: "fake-offline-code",
        grant_type: "authorization_code"
      ]

      token_data = %{@token_data | "token_type" => "bearer", "scope" => "domains:*"}

      assert {:ok,
              {%ReqDnsimple.OAuth.Token{
                 token_type: "bearer",
                 scope: "domains:*"
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.OAuth.exchange_code(client(200, token_data), attrs)

      assert_request(:post, "/v2/oauth/access_token", %{}, Map.new(attrs))
      refute_received {:request, _request}
    end

    test "oauthToken forwards both credentials and explicit empty redirect URI and state" do
      attrs = [
        client_id: "fake-offline-client",
        client_secret: "fake-offline-secret",
        code: "fake-offline-code",
        grant_type: "authorization_code",
        code_verifier: String.duplicate("Z", 128),
        redirect_uri: "",
        state: ""
      ]

      assert {:ok, {%ReqDnsimple.OAuth.Token{}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.OAuth.exchange_code(client(200, @token_data), attrs)

      assert_request(:post, "/v2/oauth/access_token", %{}, Map.new(attrs))
    end

    test "oauthToken rejects invalid containers, fields, credentials, and PKCE verifiers before HTTP" do
      request = client(200, @token_data)

      required = [
        client_id: "fake-offline-client",
        code: "fake-offline-code",
        grant_type: "authorization_code"
      ]

      invalid_attrs = [
        [:invalid],
        [{:name}],
        Map.new(required),
        [],
        Keyword.delete(required, :client_id),
        Keyword.delete(required, :code),
        Keyword.delete(required, :grant_type),
        required,
        Keyword.put(required, :client_id, nil),
        Keyword.put(required, :client_id, 0),
        Keyword.put(required, :code, nil),
        Keyword.put(required, :code, false),
        Keyword.put(required, :grant_type, "client_credentials"),
        Keyword.put(required, :grant_type, nil),
        Keyword.put(required, :client_secret, nil),
        Keyword.put(required, :client_secret, []),
        Keyword.put(required, :redirect_uri, nil),
        Keyword.put(required, :redirect_uri, 0),
        Keyword.put(required, :state, nil),
        Keyword.put(required, :state, %{}),
        Keyword.put(required, :code_verifier, String.duplicate("a", 42)),
        Keyword.put(required, :code_verifier, String.duplicate("a", 129)),
        Keyword.put(required, :code_verifier, String.duplicate("a", 42) <> "!"),
        Keyword.put(required, :code_verifier, nil),
        Keyword.put(required, :unknown, true)
      ]

      for attrs <- invalid_attrs do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.OAuth.exchange_code(request, attrs)
      end

      refute_received {:request, _request}
    end

    test "oauthToken preserves OAuth and shared HTTP failures" do
      failures = [
        {400,
         %{
           "error" => "invalid_grant",
           "error_description" => "Fake offline invalid grant"
         }},
        {400,
         %{
           "error" => "invalid_request",
           "error_description" => "Fake offline invalid request"
         }},
        {401,
         %{
           "error" => "invalid_client",
           "error_description" => "Fake offline invalid client"
         }},
        {403, %{"message" => "Fake offline forbidden"}},
        {429, %{"message" => "Fake offline rate limit"}},
        {500, "Fake offline server failure"},
        {418, nil}
      ]

      for {status, body} <- failures do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.OAuth.exchange_code(client(status, body),
                   client_id: "fake-offline-client",
                   client_secret: "fake-offline-secret",
                   code: "fake-offline-code",
                   grant_type: "authorization_code"
                 )

        assert_request(
          :post,
          "/v2/oauth/access_token",
          %{},
          %{
            client_id: "fake-offline-client",
            client_secret: "fake-offline-secret",
            code: "fake-offline-code",
            grant_type: "authorization_code"
          }
        )

        refute_received {:request, _request}
      end
    end

    test "oauthToken returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        Map.delete(@token_data, "access_token"),
        Map.delete(@token_data, "token_type"),
        Map.delete(@token_data, "scope"),
        Map.delete(@token_data, "account_id"),
        %{@token_data | "access_token" => nil},
        %{@token_data | "token_type" => nil},
        %{@token_data | "scope" => 0},
        %{@token_data | "account_id" => "1010"}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.OAuth.exchange_code(client(200, body),
                   client_id: "fake-offline-client",
                   client_secret: "fake-offline-secret",
                   code: "fake-offline-code",
                   grant_type: "authorization_code"
                 )

        assert_request(
          :post,
          "/v2/oauth/access_token",
          %{},
          %{
            client_id: "fake-offline-client",
            client_secret: "fake-offline-secret",
            code: "fake-offline-code",
            grant_type: "authorization_code"
          }
        )
      end
    end

    test "oauthToken preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.OAuth.exchange_code(transport_error_client(:timeout),
                 client_id: "fake-offline-client",
                 client_secret: "fake-offline-secret",
                 code: "fake-offline-code",
                 grant_type: "authorization_code"
               )
    end
  end

  defp authorize_client(base_url \\ "https://api.dnsimple.com/v2") do
    client(200, @token_data) |> Req.Request.put_option(:base_url, base_url)
  end
end
