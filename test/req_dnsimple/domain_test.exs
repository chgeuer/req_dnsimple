defmodule ReqDnsimple.DomainTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @domain_data %{
    "id" => 1,
    "account_id" => 1010,
    "registrant_id" => nil,
    "name" => "example.test",
    "unicode_name" => "example.test",
    "state" => "hosted",
    "auto_renew" => false,
    "private_whois" => false,
    "expires_at" => nil,
    "trustee" => false,
    "expires_on" => nil,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  describe "get/3" do
    test "getDomain sends one bodyless request and returns a typed hosted domain" do
      assert {:ok,
              %ReqDnsimple.Domain{
                id: 1,
                account_id: 1010,
                registrant_id: nil,
                name: "example.test",
                unicode_name: "example.test",
                state: "hosted",
                auto_renew: false,
                private_whois: false,
                expires_at: nil,
                trustee: false,
                expires_on: nil,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.Domain.get(
                 client(200, %{"data" => @domain_data}),
                 1010,
                 "example.test"
               )

      assert_request(:get, "/v2/1010/domains/example.test", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomain decodes a registered domain with offset timestamps and expiry dates" do
      data =
        Map.merge(@domain_data, %{
          "registrant_id" => 11,
          "state" => "registered",
          "auto_renew" => true,
          "private_whois" => true,
          "expires_at" => "2027-09-01T10:00:00+02:00",
          "expires_on" => "2027-09-01"
        })

      assert {:ok,
              %ReqDnsimple.Domain{
                registrant_id: 11,
                state: "registered",
                auto_renew: true,
                private_whois: true,
                expires_at: ~U[2027-09-01 08:00:00Z],
                expires_on: ~D[2027-09-01]
              }} = ReqDnsimple.Domain.get(client(200, %{"data" => data}), 1010, 1)

      assert_request(:get, "/v2/1010/domains/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomain accepts an older payload omitting trustee" do
      data = Map.delete(@domain_data, "trustee")

      assert {:ok, %ReqDnsimple.Domain{trustee: nil, state: "hosted"}} =
               ReqDnsimple.Domain.get(client(200, %{"data" => data}), 1010, "example.test")

      assert_request(:get, "/v2/1010/domains/example.test")
    end

    test "getDomain accepts older payloads omitting expires_on and trustee" do
      for omitted_fields <- [["expires_on"], ["expires_on", "trustee"]] do
        data = Map.drop(@domain_data, omitted_fields)

        assert {:ok, %ReqDnsimple.Domain{expires_on: nil, state: "hosted"} = domain} =
                 ReqDnsimple.Domain.get(client(200, %{"data" => data}), 1010, "example.test")

        if "trustee" in omitted_fields, do: assert(domain.trustee == nil)
        assert_request(:get, "/v2/1010/domains/example.test")
        refute_received {:request, _request}
      end
    end

    test "getDomain rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @domain_data})

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Domain.get(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "getDomain preserves explicit zero identifiers" do
      data = Map.merge(@domain_data, %{"id" => 0, "account_id" => 0})

      assert {:ok, %ReqDnsimple.Domain{id: 0, account_id: 0}} =
               ReqDnsimple.Domain.get(client(200, %{"data" => data}), 0, 0)

      assert_request(:get, "/v2/0/domains/0", %{}, nil)
    end

    test "getDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Domain.get(client(status, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/domains/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomain returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@domain_data, "name")},
        %{"data" => Map.put(@domain_data, "state", "unknown")},
        %{"data" => Map.put(@domain_data, "auto_renew", 0)},
        %{"data" => Map.put(@domain_data, "registrant_id", "11")},
        %{"data" => Map.put(@domain_data, "expires_at", "not-a-timestamp")},
        %{"data" => Map.put(@domain_data, "expires_on", "not-a-date")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Domain.get(client(200, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/domains/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomain preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Domain.get(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "delete/3" do
    test "deleteDomain sends one bodyless request and returns :ok" do
      assert :ok = ReqDnsimple.Domain.delete(client(204, ""), 1010, "example.test")

      assert_request(:delete, "/v2/1010/domains/example.test", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomain accepts an integer domain ID" do
      assert :ok = ReqDnsimple.Domain.delete(client(204, nil), 1010, 42)

      assert_request(:delete, "/v2/1010/domains/42", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomain rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Domain.delete(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "deleteDomain preserves explicit zero identifiers" do
      assert :ok = ReqDnsimple.Domain.delete(client(204, nil), 0, 0)

      assert_request(:delete, "/v2/0/domains/0", %{}, nil)
    end

    test "deleteDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["cannot be deleted"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Domain.delete(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomain rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Domain.delete(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomain preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Domain.delete(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end
end
