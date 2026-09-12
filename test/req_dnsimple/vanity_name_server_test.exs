defmodule ReqDnsimple.VanityNameServerTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "disable/3" do
    test "disableVanityNameServers sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.VanityNameServer.disable(
                 client(204, ""),
                 1010,
                 "example.test"
               )

      assert_request(:delete, "/v2/1010/vanity/example.test", %{}, nil)
      refute_received {:request, _request}
    end

    test "disableVanityNameServers accepts integer and explicit zero identifiers" do
      for {account_id, domain} <- [{1010, 42}, {0, 0}] do
        assert :ok =
                 ReqDnsimple.VanityNameServer.disable(
                   client(204, nil),
                   account_id,
                   domain
                 )

        assert_request(:delete, "/v2/#{account_id}/vanity/#{domain}", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "disableVanityNameServers preserves an explicit empty domain name" do
      assert :ok = ReqDnsimple.VanityNameServer.disable(client(204, nil), 1010, "")

      assert_request(:delete, "/v2/1010/vanity/", %{}, nil)
      refute_received {:request, _request}
    end

    test "disableVanityNameServers rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.VanityNameServer.disable(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "disableVanityNameServers preserves documented and shared HTTP failures" do
      for status <- [400, 401, 402, 403, 404, 412, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["cannot disable vanity name servers"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.VanityNameServer.disable(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:delete, "/v2/1010/vanity/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "disableVanityNameServers rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.VanityNameServer.disable(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:delete, "/v2/1010/vanity/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "disableVanityNameServers preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.VanityNameServer.disable(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end
end
