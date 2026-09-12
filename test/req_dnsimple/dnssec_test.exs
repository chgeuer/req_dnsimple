defmodule ReqDnsimple.DnssecTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @dnssec_data %{
    "enabled" => true,
    "active" => false,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  describe "get/3" do
    test "getDomainDnssec sends one bodyless request and returns typed DNSSEC status" do
      assert {:ok,
              %ReqDnsimple.Dnssec{
                enabled: true,
                active: false,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.Dnssec.get(
                 client(200, %{"data" => @dnssec_data}),
                 1010,
                 "example.test"
               )

      assert_request(:get, "/v2/1010/domains/example.test/dnssec", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomainDnssec preserves disabled state and omitted optional active flag" do
      data =
        @dnssec_data
        |> Map.put("enabled", false)
        |> Map.delete("active")

      assert {:ok, %ReqDnsimple.Dnssec{enabled: false, active: nil}} =
               ReqDnsimple.Dnssec.get(client(200, %{"data" => data}), 1010, 42)

      assert_request(:get, "/v2/1010/domains/42/dnssec", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomainDnssec rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @dnssec_data})

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Dnssec.get(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "getDomainDnssec preserves explicit zero and empty identifiers" do
      for {account_id, domain} <- [{0, 0}, {1010, ""}] do
        assert {:ok, %ReqDnsimple.Dnssec{}} =
                 ReqDnsimple.Dnssec.get(
                   client(200, %{"data" => @dnssec_data}),
                   account_id,
                   domain
                 )

        assert_request(:get, "/v2/#{account_id}/domains/#{domain}/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomainDnssec preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"dnssec" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Dnssec.get(client(status, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomainDnssec returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@dnssec_data, "enabled")},
        %{"data" => Map.put(@dnssec_data, "enabled", 1)},
        %{"data" => Map.put(@dnssec_data, "active", nil)},
        %{"data" => Map.put(@dnssec_data, "created_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Dnssec.get(client(200, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [{201, %{"data" => @dnssec_data}}, {204, nil}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Dnssec.get(client(status, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomainDnssec preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Dnssec.get(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

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
