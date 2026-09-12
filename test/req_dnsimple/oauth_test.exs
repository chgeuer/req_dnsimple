defmodule ReqDnsimple.OAuthTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @token_data %{
    "access_token" => "fake-offline-access-token",
    "token_type" => "Bearer",
    "scope" => nil,
    "account_id" => 1010
  }

  describe "exchange_code/2" do
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
              %ReqDnsimple.OAuth.Token{
                access_token: "fake-offline-access-token",
                token_type: "Bearer",
                scope: nil,
                account_id: 1010
              }} = ReqDnsimple.OAuth.exchange_code(request, attrs)

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
              %ReqDnsimple.OAuth.Token{
                token_type: "bearer",
                scope: "domains:*"
              }} = ReqDnsimple.OAuth.exchange_code(client(200, token_data), attrs)

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

      assert {:ok, %ReqDnsimple.OAuth.Token{}} =
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
        assert {:error, %NimbleOptions.ValidationError{}} =
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
        assert {:error, %{status: ^status, response: ^body}} =
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
        assert {:error, %{status: 200, response: ^body}} =
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
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.OAuth.exchange_code(transport_error_client(:timeout),
                 client_id: "fake-offline-client",
                 client_secret: "fake-offline-secret",
                 code: "fake-offline-code",
                 grant_type: "authorization_code"
               )
    end
  end
end
