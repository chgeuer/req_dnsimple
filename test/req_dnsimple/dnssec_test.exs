defmodule ReqDnsimple.DnssecTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "disable/3" do
    test "disableDomainDnssec sends one bodyless request and returns :ok" do
      assert :ok = ReqDnsimple.Dnssec.disable(client(204, ""), 1010, "example.test")

      assert_request(:delete, "/v2/1010/domains/example.test/dnssec", %{}, nil)
      refute_received {:request, _request}
    end

    test "disableDomainDnssec accepts integer and empty domain identifiers" do
      for domain <- [42, ""] do
        assert :ok = ReqDnsimple.Dnssec.disable(client(204, nil), 1010, domain)

        assert_request(:delete, "/v2/1010/domains/#{domain}/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "disableDomainDnssec rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Dnssec.disable(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "disableDomainDnssec preserves explicit zero identifiers" do
      assert :ok = ReqDnsimple.Dnssec.disable(client(204, nil), 0, 0)

      assert_request(:delete, "/v2/0/domains/0/dnssec", %{}, nil)
      refute_received {:request, _request}
    end

    test "disableDomainDnssec preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 428, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"dnssec" => ["cannot be disabled"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Dnssec.disable(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "disableDomainDnssec rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Dnssec.disable(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "disableDomainDnssec preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Dnssec.disable(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end
end
