defmodule ReqDnsimple.RegistrarTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "check/3" do
    test "checkDomain sends one bodyless request and returns a typed result" do
      body = %{
        "data" => %{
          "domain" => "example.test",
          "available" => true,
          "premium" => true,
          "trustee" => true
        }
      }

      assert {:ok,
              %ReqDnsimple.Registrar.CheckResult{
                domain: "example.test",
                available: true,
                premium: true,
                trustee: true
              }} = ReqDnsimple.Registrar.check(client(200, body), 1010, "example.test")

      assert_request(:get, "/v2/1010/registrar/domains/example.test/check", %{}, nil)
      refute_received {:request, _request}
    end

    test "checkDomain preserves false booleans and permits an omitted trustee" do
      body = %{
        "data" => %{
          "domain" => "",
          "available" => false,
          "premium" => false
        }
      }

      assert {:ok,
              %ReqDnsimple.Registrar.CheckResult{
                domain: "",
                available: false,
                premium: false,
                trustee: nil
              }} = ReqDnsimple.Registrar.check(client(200, body), 0, "")

      assert_request(:get, "/v2/0/registrar/domains//check", %{}, nil)
      refute_received {:request, _request}
    end

    test "checkDomain rejects invalid path parameters before HTTP" do
      request =
        client(200, %{
          "data" => %{"domain" => "example.test", "available" => true, "premium" => false}
        })

      for {account_id, domain_name} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 42},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.check(request, account_id, domain_name)
      end

      refute_received {:request, _request}
    end

    test "checkDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.check(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/registrar/domains/example.test/check", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "checkDomain preserves Retry-After without retrying" do
      test_pid = self()
      body = %{"message" => "Fake registrar check rate limit"}

      adapter = fn request ->
        send(test_pid, {:request, request})

        response =
          %Req.Response{status: 429, body: body}
          |> Req.Response.put_header("retry-after", "60")

        {request, response}
      end

      request =
        ReqDnsimple.new_client("dnsimple_u_fake-token")
        |> Req.merge(adapter: adapter, retry: :transient)

      assert {:error, %{status: 429, response: ^body, retry_after: "60"}} =
               ReqDnsimple.Registrar.check(request, 1010, "example.test")

      assert_request(:get, "/v2/1010/registrar/domains/example.test/check", %{}, nil)
      refute_received {:request, _request}
    end

    test "checkDomain returns explicit errors for malformed successful responses" do
      valid_data = %{
        "domain" => "example.test",
        "available" => true,
        "premium" => false,
        "trustee" => nil
      }

      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(valid_data, "domain")},
        %{"data" => Map.delete(valid_data, "available")},
        %{"data" => Map.delete(valid_data, "premium")},
        %{"data" => Map.put(valid_data, "domain", 42)},
        %{"data" => Map.put(valid_data, "available", nil)},
        %{"data" => Map.put(valid_data, "premium", "false")},
        %{"data" => Map.put(valid_data, "trustee", 0)}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Registrar.check(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/registrar/domains/example.test/check", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "checkDomain preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.check(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "authorize_transfer_out/3" do
    test "authorizeDomainTransferOut sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.Registrar.authorize_transfer_out(
                 client(204, ""),
                 1010,
                 "example.test"
               )

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/authorize_transfer_out",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "authorizeDomainTransferOut preserves explicit zero and empty identifiers" do
      assert :ok = ReqDnsimple.Registrar.authorize_transfer_out(client(204, nil), 0, "")

      assert_request(:post, "/v2/0/registrar/domains//authorize_transfer_out", %{}, nil)
      refute_received {:request, _request}
    end

    test "authorizeDomainTransferOut rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain_name} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 42},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.authorize_transfer_out(
                   request,
                   account_id,
                   domain_name
                 )
      end

      refute_received {:request, _request}
    end

    test "authorizeDomainTransferOut preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["cannot be transferred"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.authorize_transfer_out(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/authorize_transfer_out",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "authorizeDomainTransferOut rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.authorize_transfer_out(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/authorize_transfer_out",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "authorizeDomainTransferOut preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.authorize_transfer_out(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "disable_auto_renewal/3" do
    test "disableDomainAutoRenewal sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.Registrar.disable_auto_renewal(
                 client(204, ""),
                 1010,
                 "example.test"
               )

      assert_request(
        :delete,
        "/v2/1010/registrar/domains/example.test/auto_renewal",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "disableDomainAutoRenewal accepts integer, zero, and empty identifiers" do
      for {account_id, domain} <- [{1010, 42}, {0, 0}, {1010, ""}] do
        assert :ok =
                 ReqDnsimple.Registrar.disable_auto_renewal(
                   client(204, nil),
                   account_id,
                   domain
                 )

        assert_request(
          :delete,
          "/v2/#{account_id}/registrar/domains/#{domain}/auto_renewal",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "disableDomainAutoRenewal rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.disable_auto_renewal(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "disableDomainAutoRenewal preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"auto_renewal" => ["cannot be disabled"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.disable_auto_renewal(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :delete,
          "/v2/1010/registrar/domains/example.test/auto_renewal",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "disableDomainAutoRenewal disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error, %{status: 500, response: ^body}} =
               ReqDnsimple.Registrar.disable_auto_renewal(
                 request,
                 1010,
                 "example.test"
               )

      assert_request(
        :delete,
        "/v2/1010/registrar/domains/example.test/auto_renewal",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "disableDomainAutoRenewal rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.disable_auto_renewal(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :delete,
          "/v2/1010/registrar/domains/example.test/auto_renewal",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "disableDomainAutoRenewal preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.disable_auto_renewal(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "change_delegation/4" do
    test "changeDomainDelegation sends the root name-server array once and returns it" do
      name_servers = ["ns1.example.test", "ns2.example.test"]

      assert {:ok, ^name_servers} =
               ReqDnsimple.Registrar.change_delegation(
                 client(200, %{"data" => name_servers}),
                 1010,
                 "example.test",
                 name_servers: name_servers
               )

      assert_request(
        :put,
        "/v2/1010/registrar/domains/example.test/delegation",
        %{},
        name_servers
      )

      refute_received {:request, _request}
    end

    test "changeDomainDelegation accepts numeric domain IDs and explicit empty arrays" do
      assert {:ok, []} =
               ReqDnsimple.Registrar.change_delegation(
                 client(200, %{"data" => []}),
                 1010,
                 42,
                 name_servers: []
               )

      assert_request(:put, "/v2/1010/registrar/domains/42/delegation", %{}, [])
      refute_received {:request, _request}
    end

    test "changeDomainDelegation rejects invalid inputs before HTTP" do
      request = client(200, %{"data" => []})

      invalid_calls = [
        {1010, "example.test", []},
        {1010, "example.test", [unknown: []]},
        {1010, "example.test", [name_servers: nil]},
        {1010, "example.test", [name_servers: "ns1.example.test"]},
        {1010, "example.test", [name_servers: ["ns1.example.test", nil]]},
        {1010, "example.test", %{"name_servers" => []}},
        {"1010", "example.test", [name_servers: []]},
        {1010, nil, [name_servers: []]},
        {1010, 1.0, [name_servers: []]}
      ]

      for {account_id, domain, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.change_delegation(
                   request,
                   account_id,
                   domain,
                   attrs
                 )
      end

      refute_received {:request, _request}
    end

    test "changeDomainDelegation preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"name_servers" => ["is invalid"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.change_delegation(
                   client(status, body),
                   1010,
                   "example.test",
                   name_servers: ["ns1.example.test"]
                 )

        assert_request(
          :put,
          "/v2/1010/registrar/domains/example.test/delegation",
          %{},
          ["ns1.example.test"]
        )

        refute_received {:request, _request}
      end
    end

    test "changeDomainDelegation disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error, %{status: 500, response: ^body}} =
               ReqDnsimple.Registrar.change_delegation(
                 request,
                 1010,
                 "example.test",
                 name_servers: ["ns1.example.test"]
               )

      assert_request(
        :put,
        "/v2/1010/registrar/domains/example.test/delegation",
        %{},
        ["ns1.example.test"]
      )

      refute_received {:request, _request}
    end

    test "changeDomainDelegation returns explicit errors for malformed success" do
      for body <- [
            %{},
            %{"data" => nil},
            %{"data" => %{}},
            %{"data" => ["ns1.example.test", nil]},
            %{"data" => [42]}
          ] do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Registrar.change_delegation(
                   client(200, body),
                   1010,
                   "example.test",
                   name_servers: []
                 )

        assert_request(
          :put,
          "/v2/1010/registrar/domains/example.test/delegation",
          %{},
          []
        )

        refute_received {:request, _request}
      end
    end

    test "changeDomainDelegation preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.change_delegation(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 name_servers: ["ns1.example.test"]
               )
    end
  end
end
