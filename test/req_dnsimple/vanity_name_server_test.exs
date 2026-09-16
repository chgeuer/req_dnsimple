defmodule ReqDnsimple.VanityNameServerTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @vanity_name_server_data %{
    "id" => 1,
    "name" => "ns1.example.test",
    "ipv4" => "192.0.2.1",
    "ipv6" => "2001:db8::1",
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  test "preserves HTTP headers on vanity configuration, empty responses, and errors" do
    headers = [
      {"x-request-id", "vanity-response"},
      {"x-ratelimit-remaining", "0"},
      {"retry-after", "5"}
    ]

    for {operation, status, body} <- [
          {&ReqDnsimple.VanityNameServer.enable(&1, 1010, "example.test"), 200,
           %{"data" => [@vanity_name_server_data]}},
          {&ReqDnsimple.VanityNameServer.disable(&1, 1010, "example.test"), 204, nil}
        ] do
      metadata = %ReqDnsimple.Metadata{
        status: status,
        request_id: "vanity-response",
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

  describe "enable/3" do
    test "enableVanityNameServers sends one bodyless request and returns typed records" do
      assert {:ok,
              {[
                 %ReqDnsimple.VanityNameServer{
                   id: 1,
                   name: "ns1.example.test",
                   ipv4: "192.0.2.1",
                   ipv6: "2001:db8::1",
                   created_at: ~U[2026-09-01 08:00:00Z],
                   updated_at: ~U[2026-09-01 08:30:00Z]
                 }
               ], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.VanityNameServer.enable(
                 client(200, %{"data" => [@vanity_name_server_data]}),
                 1010,
                 "example.test"
               )

      assert_request(:put, "/v2/1010/vanity/example.test", %{}, nil)
      refute_received {:request, _request}
    end

    test "enableVanityNameServers preserves an empty collection" do
      assert {:ok, {[], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.VanityNameServer.enable(
                 client(200, %{"data" => []}),
                 1010,
                 "example.test"
               )

      assert_request(:put, "/v2/1010/vanity/example.test", %{}, nil)
      refute_received {:request, _request}
    end

    test "enableVanityNameServers accepts integer, zero, and empty identifiers" do
      for {account_id, domain} <- [{1010, 42}, {0, 0}, {1010, ""}] do
        assert {:ok, {[%ReqDnsimple.VanityNameServer{}], %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.VanityNameServer.enable(
                   client(200, %{"data" => [@vanity_name_server_data]}),
                   account_id,
                   domain
                 )

        assert_request(:put, "/v2/#{account_id}/vanity/#{domain}", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "enableVanityNameServers rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => [@vanity_name_server_data]})

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.VanityNameServer.enable(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "enableVanityNameServers preserves documented and shared HTTP failures" do
      for status <- [400, 401, 402, 403, 404, 412, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["cannot enable vanity name servers"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.VanityNameServer.enable(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:put, "/v2/1010/vanity/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "enableVanityNameServers returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        %{"data" => [Map.delete(@vanity_name_server_data, "ipv4")]},
        %{"data" => [Map.put(@vanity_name_server_data, "id", "1")]},
        %{"data" => [Map.put(@vanity_name_server_data, "ipv6", nil)]},
        %{"data" => [Map.put(@vanity_name_server_data, "created_at", "not-a-timestamp")]}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.VanityNameServer.enable(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:put, "/v2/1010/vanity/example.test", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [{201, %{"data" => [@vanity_name_server_data]}}, {204, nil}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.VanityNameServer.enable(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:put, "/v2/1010/vanity/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "enableVanityNameServers preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.VanityNameServer.enable(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "disable/3" do
    test "disableVanityNameServers sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
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
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
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
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.VanityNameServer.disable(client(204, nil), 1010, "")

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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.VanityNameServer.disable(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end
end
