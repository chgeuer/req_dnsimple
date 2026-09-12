defmodule ReqDnsimpleTest do
  use ExUnit.Case
  doctest ReqDnsimple

  import ReqDnsimple.TestSupport

  describe "new_client/1" do
    test "adds bearer authentication for static and callback tokens" do
      assert_request_auth(ReqDnsimple.new_client("static-token"), "Bearer static-token")

      assert_request_auth(
        ReqDnsimple.new_client(fn -> "dynamic-token" end),
        "Bearer dynamic-token"
      )
    end

    test "resolves callback tokens lazily for every request" do
      {:ok, tokens} = Agent.start_link(fn -> ["first-token", "second-token"] end)

      client =
        ReqDnsimple.new_client(fn ->
          Agent.get_and_update(tokens, fn [token | rest] -> {token, rest} end)
        end)

      assert Agent.get(tokens, & &1) == ["first-token", "second-token"]

      assert_request_auth(client, "Bearer first-token")
      assert_request_auth(client, "Bearer second-token")
    end

    test "preserves callbacks that return bearer tuples" do
      client = ReqDnsimple.new_client(fn -> {:bearer, "tuple-token"} end)

      assert_request_auth(client, "Bearer tuple-token")
    end
  end

  describe "whoami/1" do
    test "selects the non-null identity from the response regardless of token prefix" do
      for {token, data, expected} <- [
            {"opaque-token", %{"user" => %{"id" => 1}, "account" => nil}, {:user, %{"id" => 1}}},
            {"dnsimple_u_fake", %{"user" => nil, "account" => %{"id" => 2}},
             {:account, %{"id" => 2}}},
            {"dnsimple_a_fake", %{"user" => %{"id" => 3}, "account" => nil},
             {:user, %{"id" => 3}}}
          ] do
        assert ReqDnsimple.whoami(whoami_client(token, data)) == expected
        assert_request(:get, "/v2/whoami")
      end
    end

    test "evaluates a dynamic token callback only once for authentication" do
      test_pid = self()

      client =
        ReqDnsimple.new_client(fn ->
          send(test_pid, :token_resolved)
          "opaque-token"
        end)
        |> with_whoami_response(%{"user" => %{"id" => 1}, "account" => nil})

      assert {:user, %{"id" => 1}} = ReqDnsimple.whoami(client)
      assert_receive :token_resolved
      refute_receive :token_resolved
      assert_request(:get, "/v2/whoami")
    end

    test "preserves the full response body when identity is ambiguous or absent" do
      for data <- [
            %{"user" => nil, "account" => nil},
            %{"user" => %{"id" => 1}, "account" => %{"id" => 2}}
          ] do
        body = %{"data" => data, "request_id" => "req-123"}

        assert ReqDnsimple.whoami(whoami_client("dnsimple_u_fake", data, body)) ==
                 {:unknown_token, body}

        assert_request(:get, "/v2/whoami")
      end
    end

    test "supports custom Req authentication configurations" do
      client =
        Req.new(base_url: "https://api.dnsimple.com/v2", auth: {:basic, "user:password"})
        |> with_whoami_response(%{"user" => nil, "account" => %{"id" => 2}})

      assert {:account, %{"id" => 2}} = ReqDnsimple.whoami(client)
      assert_request(:get, "/v2/whoami")
    end

    test "returns transport errors without exposing authentication" do
      client =
        ReqDnsimple.new_client("opaque-secret")
        |> Req.merge(
          adapter: fn request ->
            {request, %Req.TransportError{reason: :econnrefused}}
          end,
          retry: false
        )

      assert {:error, %Req.TransportError{reason: :econnrefused} = error} =
               ReqDnsimple.whoami(client)

      refute inspect(error) =~ "opaque-secret"
    end
  end

  defp assert_request_auth(client, expected_authorization) do
    test_pid = self()

    adapter = fn request ->
      send(
        test_pid,
        {:request, request.method, URI.to_string(request.url),
         Req.Request.get_header(request, "authorization")}
      )

      {request, %Req.Response{status: 200, body: %{}}}
    end

    assert {:ok, %Req.Response{status: 200}} =
             Req.get(client, url: "/whoami", adapter: adapter)

    assert_receive {:request, :get, "https://api.dnsimple.com/v2/whoami",
                    [^expected_authorization]}
  end

  defp whoami_client(token, data, body \\ nil) do
    token
    |> ReqDnsimple.new_client()
    |> with_whoami_response(data, body)
  end

  defp with_whoami_response(client, data, body \\ nil) do
    test_pid = self()
    body = body || %{"data" => data}

    Req.merge(client,
      adapter: fn request ->
        send(test_pid, {:request, request})
        {request, %Req.Response{status: 200, body: body}}
      end,
      retry: false
    )
  end
end
