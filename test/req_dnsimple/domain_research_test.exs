defmodule ReqDnsimple.DomainResearchTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @research_data %{
    "request_id" => "00000000-0000-4000-8000-000000000001",
    "domain" => "example.test",
    "availability" => "unknown",
    "errors" => ["Fake offline research limitation"]
  }

  describe "get_status/3" do
    test "getDomainsResearchStatus sends one bodyless request and returns a typed result" do
      assert {:ok,
              %ReqDnsimple.DomainResearch{
                request_id: "00000000-0000-4000-8000-000000000001",
                domain: "example.test",
                availability: "unknown",
                errors: ["Fake offline research limitation"]
              }} =
               ReqDnsimple.DomainResearch.get_status(
                 client(200, %{"data" => @research_data}),
                 1010,
                 domain: "example.test"
               )

      assert_request(
        :get,
        "/v2/1010/domains/research/status",
        %{"domain" => "example.test"},
        nil
      )

      refute_received {:request, _request}
    end

    test "getDomainsResearchStatus preserves all availability values and error lists" do
      for {availability, errors} <- [
            {"available", []},
            {"unavailable", ["Fake registry response"]},
            {"unknown", ["Fake offline research limitation"]}
          ] do
        data = Map.merge(@research_data, %{"availability" => availability, "errors" => errors})

        assert {:ok,
                %ReqDnsimple.DomainResearch{
                  availability: ^availability,
                  errors: ^errors
                }} =
                 ReqDnsimple.DomainResearch.get_status(
                   client(200, %{"data" => data}),
                   1010,
                   domain: "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/research/status", %{
          "domain" => "example.test"
        })

        refute_received {:request, _request}
      end
    end

    test "getDomainsResearchStatus preserves an explicit empty domain query" do
      data = Map.put(@research_data, "domain", "")

      assert {:ok, %ReqDnsimple.DomainResearch{domain: ""}} =
               ReqDnsimple.DomainResearch.get_status(
                 client(200, %{"data" => data}),
                 0,
                 domain: ""
               )

      assert_request(:get, "/v2/0/domains/research/status", %{"domain" => ""}, nil)
    end

    test "getDomainsResearchStatus rejects missing, invalid, and unknown options before HTTP" do
      request = client(200, %{"data" => @research_data})

      for {account_id, opts} <- [
            {"1010", [domain: "example.test"]},
            {nil, [domain: "example.test"]},
            {1010, []},
            {1010, [domain: nil]},
            {1010, [domain: 0]},
            {1010, [domain: "example.test", unsupported: true]}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.DomainResearch.get_status(request, account_id, opts)
      end

      refute_received {:request, _request}
    end

    test "getDomainsResearchStatus preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DomainResearch.get_status(
                   client(status, body),
                   1010,
                   domain: "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/research/status", %{
          "domain" => "example.test"
        })

        refute_received {:request, _request}
      end
    end

    test "getDomainsResearchStatus preserves monthly-cap Retry-After without retrying" do
      body = %{"message" => "Fake monthly research cap reached"}

      assert {:error, %{status: 429, response: ^body, retry_after: "3600"}} =
               ReqDnsimple.DomainResearch.get_status(
                 client_with_headers(429, body, [{"retry-after", "3600"}]),
                 1010,
                 domain: "example.test"
               )

      assert_request(:get, "/v2/1010/domains/research/status", %{
        "domain" => "example.test"
      })

      refute_received {:request, _request}
    end

    test "getDomainsResearchStatus returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@research_data, "request_id")},
        %{"data" => Map.put(@research_data, "domain", nil)},
        %{"data" => Map.put(@research_data, "availability", "pending")},
        %{"data" => Map.put(@research_data, "errors", [nil])}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.DomainResearch.get_status(
                   client(200, body),
                   1010,
                   domain: "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/research/status", %{
          "domain" => "example.test"
        })

        refute_received {:request, _request}
      end
    end

    test "getDomainsResearchStatus preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.DomainResearch.get_status(
                 transport_error_client(:timeout),
                 1010,
                 domain: "example.test"
               )
    end
  end

  defp client_with_headers(status, body, headers) do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:request, request})

      response =
        Enum.reduce(headers, %Req.Response{status: status, body: body}, fn {name, value},
                                                                           response ->
          Req.Response.put_header(response, name, value)
        end)

      {request, response}
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
