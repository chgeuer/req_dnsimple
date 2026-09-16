defmodule ReqDnsimple.DnssecTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @dnssec_data %{
    "enabled" => true,
    "active" => false,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  test "preserves HTTP headers on DNSSEC success, empty responses, and errors" do
    headers = [
      {"x-request-id", "dnssec-response"},
      {"x-ratelimit-remaining", "0"},
      {"retry-after", "5"}
    ]

    for {operation, status, body} <- [
          {&ReqDnsimple.Dnssec.get(&1, 1010, "example.test"), 200, %{"data" => @dnssec_data}},
          {&ReqDnsimple.Dnssec.enable(&1, 1010, "example.test"), 201, %{"data" => @dnssec_data}},
          {&ReqDnsimple.Dnssec.disable(&1, 1010, "example.test"), 204, nil}
        ] do
      metadata = %ReqDnsimple.Metadata{
        status: status,
        request_id: "dnssec-response",
        rate_limit_remaining: 0,
        retry_after: "5"
      }

      assert {:ok, {data, ^metadata}} = operation.(client(status, body, self(), headers))
      if status == 204, do: assert(is_nil(data))
      assert_received {:request, _request}

      error_body = %{"message" => "retry later"}
      error_metadata = %{metadata | status: 429}

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 429, response: ^error_body},
                metadata: ^error_metadata
              }} = operation.(client(429, error_body, self(), headers))

      assert_received {:request, _request}
      refute_received {:request, _request}
    end
  end

  describe "get/3" do
    test "getDomainDnssec sends one bodyless request and returns typed DNSSEC status" do
      assert {:ok,
              {%ReqDnsimple.Dnssec{
                 enabled: true,
                 active: false,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
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

      assert {:ok, {%ReqDnsimple.Dnssec{enabled: false, active: nil}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Dnssec.get(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "getDomainDnssec preserves explicit zero and empty identifiers" do
      for {account_id, domain} <- [{0, 0}, {1010, ""}] do
        assert {:ok, {%ReqDnsimple.Dnssec{}, %ReqDnsimple.Metadata{}}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Dnssec.get(client(200, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [{201, %{"data" => @dnssec_data}}, {204, nil}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Dnssec.get(client(status, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomainDnssec preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Dnssec.get(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "enable/3" do
    test "enableDomainDnssec sends one bodyless request and returns typed DNSSEC status" do
      assert {:ok,
              {%ReqDnsimple.Dnssec{
                 enabled: true,
                 active: false,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Dnssec.enable(
                 client(201, %{"data" => @dnssec_data}),
                 1010,
                 "example.test"
               )

      assert_request(:post, "/v2/1010/domains/example.test/dnssec", %{}, nil)
      refute_received {:request, _request}
    end

    test "enableDomainDnssec permits omitted active and rejects explicit null" do
      omitted_active = %{"data" => Map.delete(@dnssec_data, "active")}

      assert {:ok, {%ReqDnsimple.Dnssec{active: nil}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Dnssec.enable(client(201, omitted_active), 1010, 42)

      assert_request(:post, "/v2/1010/domains/42/dnssec", %{}, nil)
      refute_received {:request, _request}

      null_active = %{"data" => Map.put(@dnssec_data, "active", nil)}

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 201, response: ^null_active},
                metadata: %ReqDnsimple.Metadata{status: 201}
              }} =
               ReqDnsimple.Dnssec.enable(client(201, null_active), 1010, "example.test")

      assert_request(:post, "/v2/1010/domains/example.test/dnssec", %{}, nil)
      refute_received {:request, _request}
    end

    test "enableDomainDnssec rejects invalid path parameters before HTTP" do
      request = client(201, %{"data" => @dnssec_data})

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Dnssec.enable(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "enableDomainDnssec preserves explicit zero and empty identifiers" do
      for {account_id, domain} <- [{0, 0}, {1010, ""}] do
        assert {:ok, {%ReqDnsimple.Dnssec{}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Dnssec.enable(
                   client(201, %{"data" => @dnssec_data}),
                   account_id,
                   domain
                 )

        assert_request(:post, "/v2/#{account_id}/domains/#{domain}/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "enableDomainDnssec preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"dnssec" => ["cannot be enabled"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Dnssec.enable(client(status, body), 1010, "example.test")

        assert_request(:post, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "enableDomainDnssec returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@dnssec_data, "enabled")},
        %{"data" => Map.put(@dnssec_data, "enabled", 1)},
        %{"data" => Map.put(@dnssec_data, "created_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 201, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 201}
                }} =
                 ReqDnsimple.Dnssec.enable(client(201, body), 1010, "example.test")

        assert_request(:post, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [{200, %{"data" => @dnssec_data}}, {204, nil}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Dnssec.enable(client(status, body), 1010, "example.test")

        assert_request(:post, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "enableDomainDnssec preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Dnssec.enable(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "disable/3" do
    test "disableDomainDnssec sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Dnssec.disable(client(204, ""), 1010, "example.test")

      assert_request(:delete, "/v2/1010/domains/example.test/dnssec", %{}, nil)
      refute_received {:request, _request}
    end

    test "disableDomainDnssec accepts integer and empty domain identifiers" do
      for domain <- [42, ""] do
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
                 ReqDnsimple.Dnssec.disable(client(204, nil), 1010, domain)

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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Dnssec.disable(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "disableDomainDnssec preserves explicit zero identifiers" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Dnssec.disable(client(204, nil), 0, 0)

      assert_request(:delete, "/v2/0/domains/0/dnssec", %{}, nil)
      refute_received {:request, _request}
    end

    test "disableDomainDnssec preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 428, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"dnssec" => ["cannot be disabled"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Dnssec.disable(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "disableDomainDnssec rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Dnssec.disable(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test/dnssec", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "disableDomainDnssec preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Dnssec.disable(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end
end
