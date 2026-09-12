defmodule ReqDnsimpleTest do
  use ExUnit.Case
  doctest ReqDnsimple

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
end
