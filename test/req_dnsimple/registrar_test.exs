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
        "trustee" => false
      }

      assert {:ok, %ReqDnsimple.Registrar.CheckResult{}} =
               ReqDnsimple.Registrar.check(
                 client(200, %{"data" => valid_data}),
                 1010,
                 "example.test"
               )

      assert_request(:get, "/v2/1010/registrar/domains/example.test/check", %{}, nil)
      refute_received {:request, _request}

      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(valid_data, "domain")},
        %{"data" => Map.delete(valid_data, "available")},
        %{"data" => Map.delete(valid_data, "premium")},
        %{"data" => Map.put(valid_data, "domain", 42)},
        %{"data" => Map.put(valid_data, "available", nil)},
        %{"data" => Map.put(valid_data, "premium", "false")},
        %{"data" => Map.put(valid_data, "trustee", nil)},
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

  describe "enable_auto_renewal/3" do
    test "enableDomainAutoRenewal sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.Registrar.enable_auto_renewal(
                 client(204, ""),
                 1010,
                 "example.test"
               )

      assert_request(
        :put,
        "/v2/1010/registrar/domains/example.test/auto_renewal",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "enableDomainAutoRenewal accepts integer, zero, and empty identifiers" do
      for {account_id, domain} <- [{1010, 42}, {0, 0}, {1010, ""}] do
        assert :ok =
                 ReqDnsimple.Registrar.enable_auto_renewal(
                   client(204, nil),
                   account_id,
                   domain
                 )

        assert_request(
          :put,
          "/v2/#{account_id}/registrar/domains/#{domain}/auto_renewal",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "enableDomainAutoRenewal rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.enable_auto_renewal(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "enableDomainAutoRenewal preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"auto_renewal" => ["cannot be enabled"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.enable_auto_renewal(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :put,
          "/v2/1010/registrar/domains/example.test/auto_renewal",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "enableDomainAutoRenewal disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error, %{status: 500, response: ^body}} =
               ReqDnsimple.Registrar.enable_auto_renewal(
                 request,
                 1010,
                 "example.test"
               )

      assert_request(
        :put,
        "/v2/1010/registrar/domains/example.test/auto_renewal",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "enableDomainAutoRenewal rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.enable_auto_renewal(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :put,
          "/v2/1010/registrar/domains/example.test/auto_renewal",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "enableDomainAutoRenewal preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.enable_auto_renewal(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "enable_whois_privacy/3" do
    test "enableWhoisPrivacy sends one bodyless request and returns typed 200 and 201 payloads" do
      body = %{
        "data" => %{
          "id" => 1,
          "domain_id" => 100,
          "enabled" => true,
          "expires_on" => "2026-09-01",
          "created_at" => "2026-09-01T10:00:00+02:00",
          "updated_at" => "2026-09-01T10:01:00+02:00"
        }
      }

      for status <- [200, 201] do
        assert {:ok,
                %ReqDnsimple.Registrar.WhoisPrivacy{
                  id: 1,
                  domain_id: 100,
                  enabled: true,
                  expires_on: ~D[2026-09-01],
                  created_at: ~U[2026-09-01 08:00:00Z],
                  updated_at: ~U[2026-09-01 08:01:00Z]
                }} =
                 ReqDnsimple.Registrar.enable_whois_privacy(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :put,
          "/v2/1010/registrar/domains/example.test/whois_privacy",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "enableWhoisPrivacy accepts integer, zero, and empty identifiers" do
      body = %{
        "data" => %{
          "id" => 0,
          "domain_id" => 0,
          "enabled" => false,
          "expires_on" => "2026-09-01",
          "created_at" => "2026-09-01T10:00:00Z",
          "updated_at" => "2026-09-01T10:00:00Z"
        }
      }

      for {account_id, domain} <- [{1010, 42}, {0, 0}, {1010, ""}] do
        assert {:ok, %ReqDnsimple.Registrar.WhoisPrivacy{enabled: false}} =
                 ReqDnsimple.Registrar.enable_whois_privacy(
                   client(200, body),
                   account_id,
                   domain
                 )

        assert_request(
          :put,
          "/v2/#{account_id}/registrar/domains/#{domain}/whois_privacy",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "enableWhoisPrivacy rejects invalid path parameters before HTTP" do
      request =
        client(200, %{
          "data" => %{
            "id" => 1,
            "domain_id" => 100,
            "enabled" => true,
            "expires_on" => "2026-09-01",
            "created_at" => "2026-09-01T10:00:00Z",
            "updated_at" => "2026-09-01T10:00:00Z"
          }
        })

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.enable_whois_privacy(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "enableWhoisPrivacy preserves documented and shared HTTP failures" do
      for status <- [400, 402, 404, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"whois_privacy" => ["cannot be enabled"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.enable_whois_privacy(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :put,
          "/v2/1010/registrar/domains/example.test/whois_privacy",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "enableWhoisPrivacy disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error, %{status: 500, response: ^body}} =
               ReqDnsimple.Registrar.enable_whois_privacy(request, 1010, "example.test")

      assert_request(
        :put,
        "/v2/1010/registrar/domains/example.test/whois_privacy",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "enableWhoisPrivacy returns explicit errors for malformed successful responses" do
      valid_data = %{
        "id" => 1,
        "domain_id" => 100,
        "enabled" => true,
        "expires_on" => "2026-09-01",
        "created_at" => "2026-09-01T10:00:00Z",
        "updated_at" => "2026-09-01T10:00:00Z"
      }

      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(valid_data, "id")},
        %{"data" => Map.put(valid_data, "id", "1")},
        %{"data" => Map.put(valid_data, "domain_id", nil)},
        %{"data" => Map.put(valid_data, "enabled", 1)},
        %{"data" => Map.put(valid_data, "expires_on", nil)},
        %{"data" => Map.put(valid_data, "expires_on", "not-a-date")},
        %{"data" => Map.put(valid_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(valid_data, "updated_at", 0)}
      ]

      for status <- [200, 201], body <- malformed_payloads do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.enable_whois_privacy(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :put,
          "/v2/1010/registrar/domains/example.test/whois_privacy",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "enableWhoisPrivacy preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.enable_whois_privacy(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "register/4" do
    test "registerDomain sends all attributes once and returns the typed 201 payload" do
      body = %{
        "data" => %{
          "id" => 1,
          "domain_id" => 100,
          "registrant_id" => 11,
          "period" => 1,
          "state" => "registered",
          "auto_renew" => false,
          "whois_privacy" => false,
          "trustee" => false,
          "created_at" => "2026-09-01T10:00:00+02:00",
          "updated_at" => "2026-09-01T10:01:00+02:00"
        }
      }

      attrs = [
        registrant_id: 11,
        whois_privacy: false,
        auto_renew: false,
        trustee: false,
        extended_attributes: %{"uk_legal_type" => "IND"},
        premium_price: "12.00",
        linked_provider: "fake-linked-provider"
      ]

      assert {:ok,
              %ReqDnsimple.Registrar.Registration{
                id: 1,
                domain_id: 100,
                registrant_id: 11,
                period: 1,
                state: "registered",
                auto_renew: false,
                whois_privacy: false,
                trustee: false,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:01:00Z]
              }} =
               ReqDnsimple.Registrar.register(
                 client(201, body),
                 1010,
                 "example.test",
                 attrs
               )

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/registrations",
        %{},
        Map.new(attrs)
      )

      refute_received {:request, _request}
    end

    test "registerDomain sends only required fields and returns the typed 202 payload" do
      body = %{
        "data" => %{
          "id" => 2,
          "domain_id" => 101,
          "registrant_id" => 0,
          "period" => 10,
          "state" => "registering",
          "auto_renew" => false,
          "whois_privacy" => false,
          "trustee" => false,
          "created_at" => "2026-09-01T10:00:00Z",
          "updated_at" => "2026-09-01T10:00:00Z"
        }
      }

      assert {:ok, %ReqDnsimple.Registrar.Registration{state: "registering", period: 10}} =
               ReqDnsimple.Registrar.register(client(202, body), 0, "", registrant_id: 0)

      assert_request(
        :post,
        "/v2/0/registrar/domains//registrations",
        %{},
        %{registrant_id: 0}
      )

      refute_received {:request, _request}
    end

    test "registerDomain preserves empty optional values and all documented states" do
      for {state, status} <- [
            {"cancelled", 201},
            {"new", 202},
            {"failed", 201}
          ] do
        body = %{
          "data" => %{
            "id" => 3,
            "domain_id" => 102,
            "registrant_id" => 11,
            "period" => 1,
            "state" => state,
            "auto_renew" => false,
            "whois_privacy" => false,
            "trustee" => false,
            "created_at" => "2026-09-01T10:00:00Z",
            "updated_at" => "2026-09-01T10:00:00Z"
          }
        }

        assert {:ok, %ReqDnsimple.Registrar.Registration{state: ^state}} =
                 ReqDnsimple.Registrar.register(
                   client(status, body),
                   1010,
                   "example.test",
                   registrant_id: 11,
                   extended_attributes: %{},
                   premium_price: "",
                   linked_provider: ""
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/registrations",
          %{},
          %{
            registrant_id: 11,
            extended_attributes: %{},
            premium_price: "",
            linked_provider: ""
          }
        )

        refute_received {:request, _request}
      end
    end

    test "registerDomain rejects invalid inputs before HTTP" do
      request =
        client(201, %{
          "data" => %{
            "id" => 1,
            "domain_id" => 100,
            "registrant_id" => 11,
            "period" => 1,
            "state" => "registered",
            "auto_renew" => false,
            "whois_privacy" => false,
            "trustee" => false,
            "created_at" => "2026-09-01T10:00:00Z",
            "updated_at" => "2026-09-01T10:00:00Z"
          }
        })

      invalid_calls = [
        {"1010", "example.test", [registrant_id: 11]},
        {nil, "example.test", [registrant_id: 11]},
        {1010, nil, [registrant_id: 11]},
        {1010, 42, [registrant_id: 11]},
        {1010, "example.test", []},
        {1010, "example.test", [registrant_id: nil]},
        {1010, "example.test", [registrant_id: "11"]},
        {1010, "example.test", [registrant_id: 11, whois_privacy: nil]},
        {1010, "example.test", [registrant_id: 11, auto_renew: 0]},
        {1010, "example.test", [registrant_id: 11, trustee: "false"]},
        {1010, "example.test", [registrant_id: 11, extended_attributes: []]},
        {1010, "example.test", [registrant_id: 11, extended_attributes: %{country: "GB"}]},
        {1010, "example.test", [registrant_id: 11, premium_price: 12.0]},
        {1010, "example.test", [registrant_id: 11, linked_provider: nil]},
        {1010, "example.test", [registrant_id: 11, period: 1]},
        {1010, "example.test", %{"registrant_id" => 11}}
      ]

      for {account_id, domain_name, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.register(request, account_id, domain_name, attrs)
      end

      refute_received {:request, _request}
    end

    test "registerDomain preserves documented and shared HTTP failures" do
      for status <- [400, 402, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"premium_price" => ["does not match"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.register(
                   client(status, body),
                   1010,
                   "example.test",
                   registrant_id: 11,
                   premium_price: "12.00"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/registrations",
          %{},
          %{registrant_id: 11, premium_price: "12.00"}
        )

        refute_received {:request, _request}
      end
    end

    test "registerDomain disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error, %{status: 500, response: ^body}} =
               ReqDnsimple.Registrar.register(request, 1010, "example.test", registrant_id: 11)

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/registrations",
        %{},
        %{registrant_id: 11}
      )

      refute_received {:request, _request}
    end

    test "registerDomain returns explicit errors for malformed successful responses" do
      valid_data = %{
        "id" => 1,
        "domain_id" => 100,
        "registrant_id" => 11,
        "period" => 1,
        "state" => "registered",
        "auto_renew" => false,
        "whois_privacy" => false,
        "trustee" => false,
        "created_at" => "2026-09-01T10:00:00Z",
        "updated_at" => "2026-09-01T10:00:00Z"
      }

      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(valid_data, "id")},
        %{"data" => Map.put(valid_data, "id", "1")},
        %{"data" => Map.put(valid_data, "domain_id", nil)},
        %{"data" => Map.put(valid_data, "registrant_id", "11")},
        %{"data" => Map.put(valid_data, "period", 0)},
        %{"data" => Map.put(valid_data, "period", 11)},
        %{"data" => Map.put(valid_data, "state", "unknown")},
        %{"data" => Map.put(valid_data, "auto_renew", nil)},
        %{"data" => Map.put(valid_data, "whois_privacy", 0)},
        %{"data" => Map.put(valid_data, "trustee", "false")},
        %{"data" => Map.put(valid_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(valid_data, "updated_at", nil)}
      ]

      for status <- [201, 202], body <- malformed_payloads do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.register(
                   client(status, body),
                   1010,
                   "example.test",
                   registrant_id: 11
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/registrations",
          %{},
          %{registrant_id: 11}
        )

        refute_received {:request, _request}
      end
    end

    test "registerDomain preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.register(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 registrant_id: 11
               )
    end
  end

  describe "transfer/4" do
    test "transferDomain sends all attributes once and returns the typed 201 payload" do
      body = %{
        "data" => %{
          "id" => 1,
          "domain_id" => 100,
          "registrant_id" => 11,
          "state" => "transferred",
          "auto_renew" => false,
          "whois_privacy" => false,
          "trustee" => false,
          "status_description" => nil,
          "created_at" => "2026-09-01T10:00:00+02:00",
          "updated_at" => "2026-09-01T10:01:00+02:00"
        }
      }

      attrs = [
        registrant_id: 11,
        auth_code: "fake-offline-transfer-code",
        whois_privacy: false,
        auto_renew: false,
        trustee: false,
        extended_attributes: %{"us_nexus" => "C11", "us_purpose" => "P3"},
        premium_price: "12.00"
      ]

      assert {:ok,
              %ReqDnsimple.Registrar.Transfer{
                id: 1,
                domain_id: 100,
                registrant_id: 11,
                state: "transferred",
                auto_renew: false,
                whois_privacy: false,
                trustee: false,
                status_description: nil,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:01:00Z]
              }} =
               ReqDnsimple.Registrar.transfer(
                 client(201, body),
                 1010,
                 "example.test",
                 attrs
               )

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/transfers",
        %{},
        Map.new(attrs)
      )

      refute_received {:request, _request}
    end

    test "transferDomain permits conditional auth code and returns the typed 202 payload" do
      body = %{
        "data" => %{
          "id" => 2,
          "domain_id" => 101,
          "registrant_id" => 0,
          "state" => "transferring",
          "auto_renew" => false,
          "whois_privacy" => false,
          "trustee" => false,
          "created_at" => "2026-09-01T10:00:00Z",
          "updated_at" => "2026-09-01T10:00:00Z"
        }
      }

      assert {:ok,
              %ReqDnsimple.Registrar.Transfer{
                state: "transferring",
                registrant_id: 0,
                status_description: nil
              }} =
               ReqDnsimple.Registrar.transfer(client(202, body), 0, "", registrant_id: 0)

      assert_request(
        :post,
        "/v2/0/registrar/domains//transfers",
        %{},
        %{registrant_id: 0}
      )

      refute_received {:request, _request}
    end

    test "transferDomain preserves empty optional values and all documented states" do
      for {state, status} <- [
            {"cancelled", 201},
            {"new", 202},
            {"failed", 201}
          ] do
        body = %{
          "data" => %{
            "id" => 3,
            "domain_id" => 102,
            "registrant_id" => 11,
            "state" => state,
            "auto_renew" => false,
            "whois_privacy" => false,
            "trustee" => false,
            "status_description" => "",
            "created_at" => "2026-09-01T10:00:00Z",
            "updated_at" => "2026-09-01T10:00:00Z"
          }
        }

        assert {:ok,
                %ReqDnsimple.Registrar.Transfer{
                  state: ^state,
                  status_description: ""
                }} =
                 ReqDnsimple.Registrar.transfer(
                   client(status, body),
                   1010,
                   "example.test",
                   registrant_id: 11,
                   auth_code: "",
                   extended_attributes: %{},
                   premium_price: ""
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/transfers",
          %{},
          %{registrant_id: 11, auth_code: "", extended_attributes: %{}, premium_price: ""}
        )

        refute_received {:request, _request}
      end
    end

    test "transferDomain rejects invalid inputs before HTTP" do
      request =
        client(201, %{
          "data" => %{
            "id" => 1,
            "domain_id" => 100,
            "registrant_id" => 11,
            "state" => "transferred",
            "auto_renew" => false,
            "whois_privacy" => false,
            "trustee" => false,
            "created_at" => "2026-09-01T10:00:00Z",
            "updated_at" => "2026-09-01T10:00:00Z"
          }
        })

      invalid_calls = [
        {"1010", "example.test", [registrant_id: 11]},
        {nil, "example.test", [registrant_id: 11]},
        {1010, nil, [registrant_id: 11]},
        {1010, 42, [registrant_id: 11]},
        {1010, "example.test", []},
        {1010, "example.test", [registrant_id: nil]},
        {1010, "example.test", [registrant_id: "11"]},
        {1010, "example.test", [registrant_id: 11, auth_code: nil]},
        {1010, "example.test", [registrant_id: 11, whois_privacy: nil]},
        {1010, "example.test", [registrant_id: 11, auto_renew: 0]},
        {1010, "example.test", [registrant_id: 11, trustee: "false"]},
        {1010, "example.test", [registrant_id: 11, extended_attributes: []]},
        {1010, "example.test", [registrant_id: 11, extended_attributes: %{country: "US"}]},
        {1010, "example.test", [registrant_id: 11, premium_price: 12.0]},
        {1010, "example.test", [registrant_id: 11, linked_provider: "provider"]},
        {1010, "example.test", %{"registrant_id" => 11}}
      ]

      for {account_id, domain_name, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.transfer(request, account_id, domain_name, attrs)
      end

      refute_received {:request, _request}
    end

    test "transferDomain preserves documented and shared HTTP failures" do
      for status <- [400, 402, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"premium_price" => ["does not match"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.transfer(
                   client(status, body),
                   1010,
                   "example.test",
                   registrant_id: 11,
                   premium_price: "12.00"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/transfers",
          %{},
          %{registrant_id: 11, premium_price: "12.00"}
        )

        refute_received {:request, _request}
      end
    end

    test "transferDomain disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error, %{status: 500, response: ^body}} =
               ReqDnsimple.Registrar.transfer(request, 1010, "example.test", registrant_id: 11)

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/transfers",
        %{},
        %{registrant_id: 11}
      )

      refute_received {:request, _request}
    end

    test "transferDomain returns explicit errors for malformed successful responses" do
      valid_data = %{
        "id" => 1,
        "domain_id" => 100,
        "registrant_id" => 11,
        "state" => "transferred",
        "auto_renew" => false,
        "whois_privacy" => false,
        "trustee" => false,
        "status_description" => nil,
        "created_at" => "2026-09-01T10:00:00Z",
        "updated_at" => "2026-09-01T10:00:00Z"
      }

      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(valid_data, "id")},
        %{"data" => Map.put(valid_data, "id", "1")},
        %{"data" => Map.put(valid_data, "domain_id", nil)},
        %{"data" => Map.put(valid_data, "registrant_id", "11")},
        %{"data" => Map.put(valid_data, "state", "unknown")},
        %{"data" => Map.put(valid_data, "auto_renew", nil)},
        %{"data" => Map.put(valid_data, "whois_privacy", 0)},
        %{"data" => Map.put(valid_data, "trustee", "false")},
        %{"data" => Map.put(valid_data, "status_description", 42)},
        %{"data" => Map.put(valid_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(valid_data, "updated_at", nil)}
      ]

      for status <- [201, 202], body <- malformed_payloads do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.transfer(
                   client(status, body),
                   1010,
                   "example.test",
                   registrant_id: 11
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/transfers",
          %{},
          %{registrant_id: 11}
        )

        refute_received {:request, _request}
      end
    end

    test "transferDomain preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.transfer(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 registrant_id: 11
               )
    end
  end

  describe "renew/3 and renew/4" do
    test "domainRenew sends all supplied attributes once and returns the typed 201 payload" do
      body = %{
        "data" => %{
          "id" => 1,
          "domain_id" => 100,
          "period" => 2,
          "state" => "renewed",
          "created_at" => "2026-09-01T10:00:00+02:00",
          "updated_at" => "2026-09-01T10:01:00+02:00"
        }
      }

      assert {:ok,
              %ReqDnsimple.Registrar.Renewal{
                id: 1,
                domain_id: 100,
                period: 2,
                state: "renewed",
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:01:00Z]
              }} =
               ReqDnsimple.Registrar.renew(
                 client(201, body),
                 1010,
                 "example.test",
                 period: 2,
                 premium_price: "20.00"
               )

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/renewals",
        %{},
        %{period: 2, premium_price: "20.00"}
      )

      refute_received {:request, _request}
    end

    test "domainRenew permits an omitted body and returns the typed 202 payload" do
      body = %{
        "data" => %{
          "id" => 2,
          "domain_id" => 101,
          "period" => 1,
          "state" => "renewing",
          "created_at" => "2026-09-01T10:00:00Z",
          "updated_at" => "2026-09-01T10:00:00Z"
        }
      }

      assert {:ok, %ReqDnsimple.Registrar.Renewal{state: "renewing"}} =
               ReqDnsimple.Registrar.renew(client(202, body), 0, "")

      assert_request(:post, "/v2/0/registrar/domains//renewals", %{}, nil)
      refute_received {:request, _request}
    end

    test "domainRenew preserves zero periods and empty premium prices" do
      body = %{
        "data" => %{
          "id" => 3,
          "domain_id" => 102,
          "period" => 1,
          "state" => "new",
          "created_at" => "2026-09-01T10:00:00Z",
          "updated_at" => "2026-09-01T10:00:00Z"
        }
      }

      assert {:ok, %ReqDnsimple.Registrar.Renewal{state: "new"}} =
               ReqDnsimple.Registrar.renew(
                 client(201, body),
                 1010,
                 "example.test",
                 period: 0,
                 premium_price: ""
               )

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/renewals",
        %{},
        %{period: 0, premium_price: ""}
      )

      refute_received {:request, _request}
    end

    test "domainRenew rejects invalid inputs before HTTP" do
      request =
        client(201, %{
          "data" => %{
            "id" => 1,
            "domain_id" => 100,
            "period" => 1,
            "state" => "renewed",
            "created_at" => "2026-09-01T10:00:00Z",
            "updated_at" => "2026-09-01T10:00:00Z"
          }
        })

      invalid_calls = [
        {"1010", "example.test", []},
        {nil, "example.test", []},
        {1010, nil, []},
        {1010, 42, []},
        {1010, "example.test", [unknown: true]},
        {1010, "example.test", [period: nil]},
        {1010, "example.test", [period: 1.5]},
        {1010, "example.test", [period: false]},
        {1010, "example.test", [premium_price: nil]},
        {1010, "example.test", [premium_price: 20]},
        {1010, "example.test", [premium_price: []]},
        {1010, "example.test", %{"period" => 1}}
      ]

      for {account_id, domain_name, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.renew(request, account_id, domain_name, attrs)
      end

      refute_received {:request, _request}
    end

    test "domainRenew preserves documented and shared HTTP failures" do
      for status <- [400, 402, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"premium_price" => ["does not match"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.renew(
                   client(status, body),
                   1010,
                   "example.test",
                   premium_price: "20.00"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/renewals",
          %{},
          %{premium_price: "20.00"}
        )

        refute_received {:request, _request}
      end
    end

    test "domainRenew disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error, %{status: 500, response: ^body}} =
               ReqDnsimple.Registrar.renew(request, 1010, "example.test")

      assert_request(:post, "/v2/1010/registrar/domains/example.test/renewals", %{}, nil)
      refute_received {:request, _request}
    end

    test "domainRenew returns explicit errors for malformed successful responses" do
      valid_data = %{
        "id" => 1,
        "domain_id" => 100,
        "period" => 2,
        "state" => "renewed",
        "created_at" => "2026-09-01T10:00:00Z",
        "updated_at" => "2026-09-01T10:00:00Z"
      }

      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(valid_data, "id")},
        %{"data" => Map.put(valid_data, "id", "1")},
        %{"data" => Map.put(valid_data, "domain_id", nil)},
        %{"data" => Map.put(valid_data, "period", 0)},
        %{"data" => Map.put(valid_data, "period", 10)},
        %{"data" => Map.put(valid_data, "state", "unknown")},
        %{"data" => Map.put(valid_data, "created_at", nil)},
        %{"data" => Map.put(valid_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(valid_data, "updated_at", 0)}
      ]

      for status <- [201, 202], body <- malformed_payloads do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.renew(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:post, "/v2/1010/registrar/domains/example.test/renewals", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "domainRenew preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.renew(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "restore/3 and restore/4" do
    test "domainRestore sends the premium price once and returns the typed 201 payload" do
      body = %{
        "data" => %{
          "id" => 1,
          "domain_id" => 100,
          "state" => "restored",
          "created_at" => "2026-09-01T10:00:00+02:00",
          "updated_at" => "2026-09-01T10:01:00+02:00"
        }
      }

      assert {:ok,
              %ReqDnsimple.Registrar.Restore{
                id: 1,
                domain_id: 100,
                state: "restored",
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:01:00Z]
              }} =
               ReqDnsimple.Registrar.restore(
                 client(201, body),
                 1010,
                 "example.test",
                 premium_price: "109.00"
               )

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/restores",
        %{},
        %{premium_price: "109.00"}
      )

      refute_received {:request, _request}
    end

    test "domainRestore permits an omitted body and returns the typed 202 payload" do
      body = %{
        "data" => %{
          "id" => 2,
          "domain_id" => 101,
          "state" => "restoring",
          "created_at" => "2026-09-01T10:00:00Z",
          "updated_at" => "2026-09-01T10:00:00Z"
        }
      }

      assert {:ok, %ReqDnsimple.Registrar.Restore{state: "restoring"}} =
               ReqDnsimple.Registrar.restore(client(202, body), 0, "")

      assert_request(:post, "/v2/0/registrar/domains//restores", %{}, nil)
      refute_received {:request, _request}
    end

    test "domainRestore preserves an empty premium price and all documented states" do
      for {state, status} <- [
            {"new", 201},
            {"restoring", 202},
            {"restored", 201},
            {"cancelled", 202}
          ] do
        body = %{
          "data" => %{
            "id" => 3,
            "domain_id" => 102,
            "state" => state,
            "created_at" => "2026-09-01T10:00:00Z",
            "updated_at" => "2026-09-01T10:00:00Z"
          }
        }

        assert {:ok, %ReqDnsimple.Registrar.Restore{state: ^state}} =
                 ReqDnsimple.Registrar.restore(
                   client(status, body),
                   1010,
                   "example.test",
                   premium_price: ""
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/restores",
          %{},
          %{premium_price: ""}
        )

        refute_received {:request, _request}
      end
    end

    test "domainRestore rejects invalid inputs before HTTP" do
      request =
        client(201, %{
          "data" => %{
            "id" => 1,
            "domain_id" => 100,
            "state" => "restored",
            "created_at" => "2026-09-01T10:00:00Z",
            "updated_at" => "2026-09-01T10:00:00Z"
          }
        })

      invalid_calls = [
        {"1010", "example.test", []},
        {nil, "example.test", []},
        {1010, nil, []},
        {1010, 42, []},
        {1010, "example.test", [unknown: true]},
        {1010, "example.test", [period: 1]},
        {1010, "example.test", [premium_price: nil]},
        {1010, "example.test", [premium_price: 0]},
        {1010, "example.test", [premium_price: false]},
        {1010, "example.test", [premium_price: []]},
        {1010, "example.test", %{"premium_price" => "109.00"}}
      ]

      for {account_id, domain_name, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.restore(request, account_id, domain_name, attrs)
      end

      refute_received {:request, _request}
    end

    test "domainRestore preserves documented and shared HTTP failures" do
      for status <- [400, 402, 404, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"premium_price" => ["does not match"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.restore(
                   client(status, body),
                   1010,
                   "example.test",
                   premium_price: "109.00"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/restores",
          %{},
          %{premium_price: "109.00"}
        )

        refute_received {:request, _request}
      end
    end

    test "domainRestore disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error, %{status: 500, response: ^body}} =
               ReqDnsimple.Registrar.restore(request, 1010, "example.test")

      assert_request(:post, "/v2/1010/registrar/domains/example.test/restores", %{}, nil)
      refute_received {:request, _request}
    end

    test "domainRestore returns explicit errors for malformed successful responses" do
      valid_data = %{
        "id" => 1,
        "domain_id" => 100,
        "state" => "restored",
        "created_at" => "2026-09-01T10:00:00Z",
        "updated_at" => "2026-09-01T10:00:00Z"
      }

      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(valid_data, "id")},
        %{"data" => Map.put(valid_data, "id", "1")},
        %{"data" => Map.put(valid_data, "domain_id", nil)},
        %{"data" => Map.put(valid_data, "state", "unknown")},
        %{"data" => Map.put(valid_data, "created_at", nil)},
        %{"data" => Map.put(valid_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(valid_data, "updated_at", 0)}
      ]

      for status <- [201, 202], body <- malformed_payloads do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.restore(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:post, "/v2/1010/registrar/domains/example.test/restores", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "domainRestore preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.restore(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "get_prices/3" do
    test "getDomainPrices sends one bodyless request and returns typed numeric prices" do
      body = %{
        "data" => %{
          "domain" => "example.test",
          "premium" => true,
          "registration_price" => 20.0,
          "renewal_price" => 21.0,
          "transfer_price" => 22.0,
          "restore_price" => 109.0,
          "trustee_price" => 3.0,
          "ignored" => "field"
        }
      }

      assert {:ok,
              %ReqDnsimple.Registrar.Prices{
                domain: "example.test",
                premium: true,
                registration_price: 20.0,
                renewal_price: 21.0,
                transfer_price: 22.0,
                restore_price: 109.0,
                trustee_price: 3.0
              }} = ReqDnsimple.Registrar.get_prices(client(200, body), 1010, "example.test")

      assert_request(:get, "/v2/1010/registrar/domains/example.test/prices", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomainPrices preserves false, zero, and omitted optional prices" do
      zero_float = 0.0

      body = %{
        "data" => %{
          "domain" => "",
          "premium" => false,
          "registration_price" => 0,
          "renewal_price" => 0.0,
          "restore_price" => 0
        }
      }

      assert {:ok,
              %ReqDnsimple.Registrar.Prices{
                domain: "",
                premium: false,
                registration_price: 0,
                renewal_price: ^zero_float,
                transfer_price: nil,
                restore_price: 0,
                trustee_price: nil
              }} = ReqDnsimple.Registrar.get_prices(client(200, body), 0, "")

      assert_request(:get, "/v2/0/registrar/domains//prices", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomainPrices rejects invalid path parameters before HTTP" do
      request = client(200, %{})

      for {account_id, domain_name} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 42},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.get_prices(request, account_id, domain_name)
      end

      refute_received {:request, _request}
    end

    test "getDomainPrices preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.get_prices(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/registrar/domains/example.test/prices", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomainPrices returns explicit errors for malformed successful responses" do
      valid = %{
        "domain" => "example.test",
        "premium" => false,
        "registration_price" => 20.0,
        "renewal_price" => 21.0,
        "restore_price" => 109.0
      }

      for body <- [
            %{},
            %{"data" => nil},
            %{"data" => Map.delete(valid, "restore_price")},
            %{"data" => Map.put(valid, "premium", "false")},
            %{"data" => Map.put(valid, "registration_price", "20.0")},
            %{"data" => Map.put(valid, "transfer_price", nil)},
            %{"data" => Map.put(valid, "trustee_price", "3.0")}
          ] do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Registrar.get_prices(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/registrar/domains/example.test/prices", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomainPrices preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.get_prices(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "get_transfer_lock/3" do
    test "getDomainTransferLock sends one bodyless request and returns typed enabled state" do
      body = %{"data" => %{"enabled" => true, "ignored" => "field"}}

      assert {:ok, %ReqDnsimple.Registrar.TransferLock{enabled: true}} =
               ReqDnsimple.Registrar.get_transfer_lock(
                 client(200, body),
                 1010,
                 "example.test"
               )

      assert_request(
        :get,
        "/v2/1010/registrar/domains/example.test/transfer_lock",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "getDomainTransferLock preserves false and accepts integer, zero, and empty identifiers" do
      assert {:ok, %ReqDnsimple.Registrar.TransferLock{enabled: false}} =
               ReqDnsimple.Registrar.get_transfer_lock(
                 client(200, %{"data" => %{"enabled" => false}}),
                 0,
                 42
               )

      assert_request(:get, "/v2/0/registrar/domains/42/transfer_lock", %{}, nil)
      refute_received {:request, _request}

      assert {:ok, %ReqDnsimple.Registrar.TransferLock{enabled: false}} =
               ReqDnsimple.Registrar.get_transfer_lock(
                 client(200, %{"data" => %{"enabled" => false}}),
                 1010,
                 ""
               )

      assert_request(:get, "/v2/1010/registrar/domains//transfer_lock", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomainTransferLock rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => %{"enabled" => true}})

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.0},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.get_transfer_lock(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "getDomainTransferLock preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.get_transfer_lock(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :get,
          "/v2/1010/registrar/domains/example.test/transfer_lock",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "getDomainTransferLock returns explicit errors for malformed success" do
      for body <- [
            %{},
            %{"data" => nil},
            %{"data" => %{}},
            %{"data" => %{"enabled" => nil}},
            %{"data" => %{"enabled" => "false"}},
            %{"data" => %{"enabled" => 0}}
          ] do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Registrar.get_transfer_lock(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :get,
          "/v2/1010/registrar/domains/example.test/transfer_lock",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "getDomainTransferLock preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.get_transfer_lock(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "get_delegation/3" do
    test "getDomainDelegation sends one bodyless request and preserves ordered hostnames" do
      name_servers = [
        "ns1.dnsimple-edge.com",
        "ns2.dnsimple.com",
        "ns3.example.test"
      ]

      assert {:ok, ^name_servers} =
               ReqDnsimple.Registrar.get_delegation(
                 client(200, %{"data" => name_servers}),
                 1010,
                 "example.test"
               )

      assert_request(
        :get,
        "/v2/1010/registrar/domains/example.test/delegation",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "getDomainDelegation accepts integer, zero, and empty identifiers" do
      assert {:ok, []} =
               ReqDnsimple.Registrar.get_delegation(client(200, %{"data" => []}), 0, 42)

      assert_request(:get, "/v2/0/registrar/domains/42/delegation", %{}, nil)
      refute_received {:request, _request}

      assert {:ok, []} =
               ReqDnsimple.Registrar.get_delegation(client(200, %{"data" => []}), 1010, "")

      assert_request(:get, "/v2/1010/registrar/domains//delegation", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomainDelegation rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => []})

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.0},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.get_delegation(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "getDomainDelegation preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.get_delegation(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :get,
          "/v2/1010/registrar/domains/example.test/delegation",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "getDomainDelegation returns explicit errors for malformed success" do
      for body <- [
            %{},
            %{"data" => nil},
            %{"data" => %{}},
            %{"data" => ["ns1.example.test", nil]},
            %{"data" => [42]}
          ] do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Registrar.get_delegation(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :get,
          "/v2/1010/registrar/domains/example.test/delegation",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "getDomainDelegation preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.get_delegation(
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
