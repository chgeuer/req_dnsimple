defmodule ReqDnsimple.RegistrarTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @registration_data %{
    "id" => 361,
    "domain_id" => 104_040,
    "registrant_id" => 2715,
    "period" => 1,
    "state" => "registering",
    "auto_renew" => false,
    "whois_privacy" => false,
    "trustee" => false,
    "created_at" => "2023-01-27T17:44:32Z",
    "updated_at" => "2023-01-27T17:44:40Z"
  }
  @renewal_data %{
    "id" => 1,
    "domain_id" => 999,
    "period" => 1,
    "state" => "renewed",
    "created_at" => "2016-12-09T19:46:45Z",
    "updated_at" => "2016-12-12T19:46:45Z"
  }
  @transfer_data %{
    "id" => 361,
    "domain_id" => 182_245,
    "registrant_id" => 2715,
    "state" => "cancelled",
    "auto_renew" => false,
    "whois_privacy" => false,
    "trustee" => false,
    "status_description" => "Canceled by customer",
    "created_at" => "2020-06-05T18:08:00Z",
    "updated_at" => "2020-06-05T18:10:01Z"
  }
  @cancel_transfer_data %{
    @transfer_data
    | "state" => "transferring",
      "status_description" => nil,
      "updated_at" => "2020-06-05T18:08:04Z"
  }
  @vanity_data %{
    "id" => 1,
    "name" => "ns1.example.com",
    "ipv4" => "127.0.0.1",
    "ipv6" => "::1",
    "created_at" => "2016-07-11T09:40:19Z",
    "updated_at" => "2016-07-11T09:40:19Z"
  }

  @response_headers [
    {"X-RateLimit-Limit", "2400"},
    {"x-ratelimit-remaining", "2399"},
    {"x-ratelimit-reset", "1790000000"},
    {"x-request-id", "offline-request"},
    {"etag", "W/\"offline-etag\""},
    {"retry-after", "Wed, 21 Oct 2015 07:28:00 GMT"}
  ]
  @response_metadata %ReqDnsimple.Metadata{
    rate_limit: 2400,
    rate_limit_remaining: 2399,
    rate_limit_reset: 1_790_000_000,
    request_id: "offline-request",
    etag: "W/\"offline-etag\"",
    retry_after: "Wed, 21 Oct 2015 07:28:00 GMT"
  }

  describe "response metadata" do
    test "every registrar operation and scoped overload preserves success and HTTP error metadata" do
      privacy = %{
        "id" => 1,
        "domain_id" => 2,
        "enabled" => nil,
        "expires_on" => nil,
        "created_at" => "2016-02-13T14:34:50Z",
        "updated_at" => "2016-02-13T14:34:50Z"
      }

      contracts = [
        {:check, [1010, "example.test"], 200,
         %{"domain" => "example.test", "available" => true, "premium" => false}},
        {:get_prices, [1010, "example.test"], 200,
         %{
           "domain" => "example.test",
           "premium" => false,
           "registration_price" => 20,
           "renewal_price" => 20,
           "restore_price" => 100
         }},
        {:get_transfer_lock, [1010, "example.test"], 200, %{"enabled" => true}},
        {:enable_transfer_lock, [1010, "example.test"], 201, %{"enabled" => true}},
        {:disable_transfer_lock, [1010, "example.test"], 200, %{"enabled" => false}},
        {:authorize_transfer_out, [1010, "example.test"], 204, nil},
        {:disable_auto_renewal, [1010, "example.test"], 204, nil},
        {:enable_auto_renewal, [1010, "example.test"], 204, nil},
        {:enable_whois_privacy, [1010, "example.test"], 200, privacy},
        {:enable_whois_privacy, [1010, "example.test"], 201, privacy},
        {:disable_whois_privacy, [1010, "example.test"], 200, privacy},
        {:renew, [1010, "example.test", []], 201, @renewal_data},
        {:renew, [1010, "example.test", []], 202, @renewal_data},
        {:register, [1010, "example.test", [registrant_id: 2715]], 201, @registration_data},
        {:register, [1010, "example.test", [registrant_id: 2715]], 202, @registration_data},
        {:transfer, [1010, "example.test", [registrant_id: 2715]], 201, @transfer_data},
        {:transfer, [1010, "example.test", [registrant_id: 2715]], 202, @transfer_data},
        {:restore, [1010, "example.test", []], 201,
         Map.take(@registration_data, ["id", "domain_id", "created_at", "updated_at"])
         |> Map.put("state", "restored")},
        {:restore, [1010, "example.test", []], 202,
         Map.take(@registration_data, ["id", "domain_id", "created_at", "updated_at"])
         |> Map.put("state", "restoring")},
        {:get_delegation, [1010, "example.test"], 200, ["ns1.example.test"]},
        {:change_delegation, [1010, "example.test", [name_servers: ["ns1.example.test"]]], 200,
         ["ns1.example.test"]},
        {:get_registration, [1010, "example.test", 361], 200, @registration_data},
        {:get_renewal, [1010, "example.test", 1], 200, @renewal_data},
        {:get_renewal, [1010, "example.test", 1], 201, @renewal_data},
        {:get_transfer, [1010, "example.test", 361], 200, @transfer_data},
        {:cancel_transfer, [1010, "example.test", 361], 202, @cancel_transfer_data},
        {:change_delegation_to_vanity,
         [1010, "example.test", [name_servers: ["ns1.example.test"]]], 200, [@vanity_data]},
        {:change_delegation_from_vanity, [1010, "example.test"], 204, nil}
      ]

      for {operation, args, status, data} <- contracts,
          scoped? <- [false, true] do
        body = if status == 204, do: nil, else: %{"data" => data}

        for {http_status, response_body} <- [
              {status, body},
              {404, %{"message" => "Offline resource not found"}}
            ] do
          req = client(http_status, response_body, self(), @response_headers)
          req = if scoped?, do: ReqDnsimple.Client.for_account(req, 1010), else: req
          call_args = if scoped?, do: tl(args), else: args
          expected_metadata = %{@response_metadata | status: http_status}

          if http_status == 404 do
            assert {:error,
                    %ReqDnsimple.Error{
                      reason: %{status: 404, response: ^response_body},
                      metadata: ^expected_metadata
                    }} = apply(ReqDnsimple.Registrar, operation, [req | call_args])
          else
            assert {:ok, {result, %ReqDnsimple.Metadata{} = metadata}} =
                     apply(ReqDnsimple.Registrar, operation, [req | call_args])

            assert metadata == expected_metadata
            assert is_nil(result) == (status == 204)
          end

          assert_receive {:request, %Req.Request{}}
          refute_received {:request, _request}
        end
      end
    end

    test "missing and malformed headers do not discard valid registrar data" do
      body = %{
        "data" => %{"domain" => "example.test", "available" => true, "premium" => false}
      }

      assert {:ok, {%ReqDnsimple.Registrar.CheckResult{}, metadata}} =
               ReqDnsimple.Registrar.check(client(200, body), 1010, "example.test")

      assert metadata == %ReqDnsimple.Metadata{status: 200}
      assert_request(:get, "/v2/1010/registrar/domains/example.test/check")

      assert {:ok,
              {%ReqDnsimple.Registrar.CheckResult{domain: "example.test"},
               %ReqDnsimple.Metadata{
                 status: 200,
                 rate_limit: nil,
                 rate_limit_remaining: 7,
                 parse_errors: %{rate_limit: {:invalid_header, ["invalid"]}}
               }}} =
               ReqDnsimple.Registrar.check(
                 client(200, body, self(),
                   "x-ratelimit-limit": "invalid",
                   "x-ratelimit-remaining": "7"
                 ),
                 1010,
                 "example.test"
               )

      assert_request(:get, "/v2/1010/registrar/domains/example.test/check")
      refute_received {:request, _request}
    end

    test "HTTP errors carry Retry-After in metadata rather than the reason" do
      body = %{"message" => "Offline rate limit"}

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 429, response: ^body} = reason,
                metadata: %ReqDnsimple.Metadata{
                  status: 429,
                  retry_after: "60",
                  request_id: "offline-rate-limit"
                }
              }} =
               ReqDnsimple.Registrar.cancel_transfer(
                 client(429, body, self(),
                   "retry-after": "60",
                   "x-request-id": "offline-rate-limit"
                 ),
                 1010,
                 "example.test",
                 361
               )

      refute Map.has_key?(reason, :retry_after)
      assert_request(:delete, "/v2/1010/registrar/domains/example.test/transfers/361")
      refute_received {:request, _request}
    end
  end

  describe "get_registration/4" do
    test "getDomainRegistration returns the official registration fixture" do
      assert {:ok,
              {%ReqDnsimple.Registrar.Registration{
                 id: 361,
                 domain_id: 104_040,
                 registrant_id: 2715,
                 period: 1,
                 state: "registering",
                 auto_renew: false,
                 whois_privacy: false,
                 trustee: false,
                 created_at: ~U[2023-01-27 17:44:32Z],
                 updated_at: ~U[2023-01-27 17:44:40Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.get_registration(
                 client(200, %{"data" => @registration_data}),
                 1010,
                 "example.com",
                 361
               )

      assert_request(:get, "/v2/1010/registrar/domains/example.com/registrations/361")
      refute_received {:request, _request}
    end

    test "getDomainRegistration preserves terminal states and zero identifiers" do
      assert_job_states(:get_registration, ["registered", "cancelled", "failed"])
      assert_job_zero_identifiers(:get_registration)
    end

    test "getDomainRegistration rejects invalid paths before HTTP" do
      assert_job_invalid_paths(:get_registration)
    end

    test "getDomainRegistration rejects malformed success bodies and statuses" do
      assert_job_malformed_success(:get_registration)
    end

    test "getDomainRegistration preserves HTTP and transport errors without retries" do
      assert_job_failures(:get_registration)
    end

    test "getDomainRegistration scoped wrapper preserves the client and rejects missing scope locally" do
      assert_job_scope(:get_registration)
    end
  end

  describe "get_renewal/4" do
    test "getDomainRenewal accepts documented 200 and legacy fixture 201 responses" do
      for status <- [200, 201] do
        assert {:ok,
                {%ReqDnsimple.Registrar.Renewal{
                   id: 1,
                   domain_id: 999,
                   period: 1,
                   state: "renewed",
                   created_at: ~U[2016-12-09 19:46:45Z],
                   updated_at: ~U[2016-12-12 19:46:45Z]
                 }, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Registrar.get_renewal(
                   client(status, %{"data" => @renewal_data}),
                   1010,
                   "example.com",
                   1
                 )

        assert_request(:get, "/v2/1010/registrar/domains/example.com/renewals/1")
        refute_received {:request, _request}
      end
    end

    test "getDomainRenewal preserves terminal states and zero identifiers" do
      assert_job_states(:get_renewal, ["renewed", "cancelled", "failed"])
      assert_job_zero_identifiers(:get_renewal)
    end

    test "getDomainRenewal rejects invalid paths before HTTP" do
      assert_job_invalid_paths(:get_renewal)
    end

    test "getDomainRenewal rejects malformed success bodies and statuses" do
      assert_job_malformed_success(:get_renewal)
    end

    test "getDomainRenewal preserves HTTP and transport errors without retries" do
      assert_job_failures(:get_renewal)
    end

    test "getDomainRenewal scoped wrapper preserves the client and rejects missing scope locally" do
      assert_job_scope(:get_renewal)
    end
  end

  describe "get_transfer/4" do
    test "getDomainTransfer preserves the official cancelled transfer and description" do
      assert {:ok,
              {%ReqDnsimple.Registrar.Transfer{
                 id: 361,
                 domain_id: 182_245,
                 registrant_id: 2715,
                 state: "cancelled",
                 auto_renew: false,
                 whois_privacy: false,
                 trustee: false,
                 status_description: "Canceled by customer",
                 created_at: ~U[2020-06-05 18:08:00Z],
                 updated_at: ~U[2020-06-05 18:10:01Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.get_transfer(
                 client(200, %{"data" => @transfer_data}),
                 1010,
                 "example.com",
                 361
               )

      assert_request(:get, "/v2/1010/registrar/domains/example.com/transfers/361")
      refute_received {:request, _request}
    end

    test "getDomainTransfer preserves terminal states and optional descriptions" do
      assert_job_states(:get_transfer, ["transferred", "cancelled", "failed"])
      assert_job_zero_identifiers(:get_transfer)

      for data <- [
            Map.delete(@transfer_data, "status_description"),
            Map.put(@transfer_data, "status_description", nil)
          ] do
        assert {:ok,
                {%ReqDnsimple.Registrar.Transfer{status_description: nil},
                 %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Registrar.get_transfer(
                   client(200, %{"data" => data}),
                   1010,
                   "example.com",
                   361
                 )

        assert_request(:get, "/v2/1010/registrar/domains/example.com/transfers/361")
        refute_received {:request, _request}
      end
    end

    test "getDomainTransfer rejects invalid paths before HTTP" do
      assert_job_invalid_paths(:get_transfer)
    end

    test "getDomainTransfer rejects malformed success bodies and statuses" do
      assert_job_malformed_success(:get_transfer)
    end

    test "getDomainTransfer preserves HTTP and transport errors without retries" do
      assert_job_failures(:get_transfer)
    end

    test "getDomainTransfer scoped wrapper preserves the client and rejects missing scope locally" do
      assert_job_scope(:get_transfer)
    end
  end

  describe "cancel_transfer/4" do
    test "cancelDomainTransfer returns the official asynchronous cancellation fixture" do
      assert {:ok,
              {%ReqDnsimple.Registrar.Transfer{
                 id: 361,
                 domain_id: 182_245,
                 registrant_id: 2715,
                 state: "transferring",
                 auto_renew: false,
                 whois_privacy: false,
                 trustee: false,
                 status_description: nil,
                 created_at: ~U[2020-06-05 18:08:00Z],
                 updated_at: ~U[2020-06-05 18:08:04Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.cancel_transfer(
                 client(202, %{"data" => @cancel_transfer_data}),
                 1010,
                 "example.com",
                 361
               )

      assert_request(:delete, "/v2/1010/registrar/domains/example.com/transfers/361")
      refute_received {:request, _request}
    end

    test "cancelDomainTransfer preserves terminal states and zero identifiers" do
      assert_job_states(:cancel_transfer, ["cancelled", "transferred", "failed"])
      assert_job_zero_identifiers(:cancel_transfer)
    end

    test "cancelDomainTransfer rejects invalid paths before HTTP" do
      assert_job_invalid_paths(:cancel_transfer)
    end

    test "cancelDomainTransfer rejects malformed success bodies and statuses" do
      assert_job_malformed_success(:cancel_transfer)
    end

    test "cancelDomainTransfer preserves HTTP and transport errors without retries" do
      assert_job_failures(:cancel_transfer)
    end

    test "cancelDomainTransfer scoped wrapper preserves the client and rejects missing scope locally" do
      assert_job_scope(:cancel_transfer)
    end
  end

  describe "change_delegation_to_vanity/4" do
    test "changeDomainDelegationToVanity sends a root array and preserves ordered typed fixtures" do
      second = %{@vanity_data | "id" => 2, "name" => "ns2.example.com"}
      names = ["ns1.example.com", "ns2.example.com"]

      assert {:ok,
              {[
                 %ReqDnsimple.VanityNameServer{
                   id: 1,
                   name: "ns1.example.com",
                   ipv4: "127.0.0.1",
                   ipv6: "::1",
                   created_at: ~U[2016-07-11 09:40:19Z],
                   updated_at: ~U[2016-07-11 09:40:19Z]
                 },
                 %ReqDnsimple.VanityNameServer{id: 2, name: "ns2.example.com"}
               ], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.change_delegation_to_vanity(
                 client(200, %{"data" => [@vanity_data, second]}),
                 1010,
                 "example.com",
                 name_servers: names
               )

      assert_request(
        :put,
        "/v2/1010/registrar/domains/example.com/delegation/vanity",
        %{},
        names
      )

      refute_received {:request, _request}
    end

    test "changeDomainDelegationToVanity preserves integer domains, empty arrays and zero IDs" do
      for domain <- [42, 0, ""] do
        assert {:ok, {[], %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Registrar.change_delegation_to_vanity(
                   client(200, %{"data" => []}),
                   0,
                   domain,
                   name_servers: []
                 )

        assert_request(:put, "/v2/0/registrar/domains/#{domain}/delegation/vanity", %{}, [])
        refute_received {:request, _request}
      end
    end

    test "changeDomainDelegationToVanity rejects invalid paths and malformed keyword attributes" do
      req = client(200, %{"data" => [@vanity_data]})

      for {account_id, domain, attrs} <- [
            {"1010", "example.com", [name_servers: []]},
            {nil, "example.com", [name_servers: []]},
            {1010, nil, [name_servers: []]},
            {1010, 1.5, [name_servers: []]},
            {1010, [], [name_servers: []]},
            {1010, "example.com", []},
            {1010, "example.com", nil},
            {1010, "example.com", %{name_servers: []}},
            {1010, "example.com", [:invalid]},
            {1010, "example.com", [{:name_servers}]},
            {1010, "example.com", [{:name_servers, []} | :invalid]},
            {1010, "example.com", [name_servers: nil]},
            {1010, "example.com", [name_servers: "ns1.example.com"]},
            {1010, "example.com", [name_servers: [nil]]},
            {1010, "example.com", [name_servers: [], unknown: true]}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.change_delegation_to_vanity(
                   req,
                   account_id,
                   domain,
                   attrs
                 )
      end

      refute_received {:request, _request}
    end

    test "changeDomainDelegationToVanity rejects malformed success bodies and statuses" do
      invalid_items =
        Enum.map(Map.keys(@vanity_data), &Map.delete(@vanity_data, &1)) ++
          Enum.map(
            [
              {"id", "1"},
              {"name", nil},
              {"ipv4", 127},
              {"ipv6", []},
              {"created_at", "not-a-timestamp"},
              {"updated_at", nil}
            ],
            fn {key, value} -> Map.put(@vanity_data, key, value) end
          )

      bodies =
        [%{}, %{"data" => nil}, %{"data" => %{}}, %{"data" => ["ns1.example.com"]}] ++
          Enum.map(invalid_items, &%{"data" => [@vanity_data, &1]})

      for body <- bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Registrar.change_delegation_to_vanity(
                   client(200, body),
                   1010,
                   "example.com",
                   name_servers: []
                 )

        assert_request(
          :put,
          "/v2/1010/registrar/domains/example.com/delegation/vanity",
          %{},
          []
        )

        refute_received {:request, _request}
      end

      for status <- [201, 202, 204] do
        body = %{"data" => [@vanity_data]}

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Registrar.change_delegation_to_vanity(
                   client(status, body),
                   1010,
                   "example.com",
                   name_servers: []
                 )

        assert_request(
          :put,
          "/v2/1010/registrar/domains/example.com/delegation/vanity",
          %{},
          []
        )

        refute_received {:request, _request}
      end
    end

    test "changeDomainDelegationToVanity preserves HTTP and transport errors without retries" do
      assert_registrar_failures(
        :change_delegation_to_vanity,
        [1010, "example.com", [name_servers: ["ns1.example.com"]]],
        :put,
        "/v2/1010/registrar/domains/example.com/delegation/vanity",
        ["ns1.example.com"]
      )
    end

    test "changeDomainDelegationToVanity scoped wrapper preserves the client and rejects missing scope locally" do
      req = configured_client(200, %{"data" => [@vanity_data]})

      assert {:ok, {[%ReqDnsimple.VanityNameServer{id: 1}], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.change_delegation_to_vanity(req, 42,
                 name_servers: ["ns1.example.com"]
               )

      assert_configured_request(
        :put,
        "/v2/1010/registrar/domains/42/delegation/vanity",
        ["ns1.example.com"]
      )

      assert {:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}} =
               ReqDnsimple.Registrar.change_delegation_to_vanity(
                 unreachable_unscoped_client(),
                 nil,
                 [:invalid]
               )
    end
  end

  describe "change_delegation_from_vanity/3" do
    test "changeDomainDelegationFromVanity sends one bodyless DELETE and returns nil data with metadata" do
      for {account_id, domain} <- [{1010, "example.com"}, {1010, 42}, {0, 0}, {0, ""}] do
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
                 ReqDnsimple.Registrar.change_delegation_from_vanity(
                   client(204, nil),
                   account_id,
                   domain
                 )

        assert_request(
          :delete,
          "/v2/#{account_id}/registrar/domains/#{domain}/delegation/vanity"
        )

        refute_received {:request, _request}
      end
    end

    test "changeDomainDelegationFromVanity rejects invalid paths before HTTP" do
      req = client(204, nil)

      for {account_id, domain} <- [
            {"1010", "example.com"},
            {nil, "example.com"},
            {1010, nil},
            {1010, []},
            {1010, 1.5}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.change_delegation_from_vanity(req, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "changeDomainDelegationFromVanity rejects unexpected successful statuses" do
      for status <- [200, 201, 202] do
        body = %{"data" => []}

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Registrar.change_delegation_from_vanity(
                   client(status, body),
                   1010,
                   "example.com"
                 )

        assert_request(:delete, "/v2/1010/registrar/domains/example.com/delegation/vanity")
        refute_received {:request, _request}
      end
    end

    test "changeDomainDelegationFromVanity preserves HTTP and transport errors without retries" do
      assert_registrar_failures(
        :change_delegation_from_vanity,
        [1010, "example.com"],
        :delete,
        "/v2/1010/registrar/domains/example.com/delegation/vanity"
      )
    end

    test "changeDomainDelegationFromVanity scoped wrapper preserves the client and rejects missing scope locally" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Registrar.change_delegation_from_vanity(
                 configured_client(204, nil),
                 "example.com"
               )

      assert_configured_request(
        :delete,
        "/v2/1010/registrar/domains/example.com/delegation/vanity"
      )

      assert {:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}} =
               ReqDnsimple.Registrar.change_delegation_from_vanity(
                 unreachable_unscoped_client(),
                 nil
               )
    end
  end

  defp job_contract(:get_registration),
    do: {:get, "registrations", [200], @registration_data, ReqDnsimple.Registrar.Registration}

  defp job_contract(:get_renewal),
    do: {:get, "renewals", [200, 201], @renewal_data, ReqDnsimple.Registrar.Renewal}

  defp job_contract(:get_transfer),
    do: {:get, "transfers", [200], @transfer_data, ReqDnsimple.Registrar.Transfer}

  defp job_contract(:cancel_transfer),
    do: {:delete, "transfers", [202], @cancel_transfer_data, ReqDnsimple.Registrar.Transfer}

  defp assert_job_states(operation, states) do
    {method, resource, [status | _], data, type} = job_contract(operation)

    for state <- states do
      assert {:ok, {result, %ReqDnsimple.Metadata{}}} =
               apply(ReqDnsimple.Registrar, operation, [
                 client(status, %{"data" => Map.put(data, "state", state)}),
                 1010,
                 "example.com",
                 data["id"]
               ])

      assert result.__struct__ == type
      assert result.state == state

      assert_request(
        method,
        "/v2/1010/registrar/domains/example.com/#{resource}/#{data["id"]}"
      )

      refute_received {:request, _request}
    end
  end

  defp assert_job_zero_identifiers(operation) do
    {method, resource, [status | _], data, _type} = job_contract(operation)
    data = Map.merge(data, %{"id" => 0, "domain_id" => 0})

    assert {:ok, {%{id: 0, domain_id: 0}, %ReqDnsimple.Metadata{}}} =
             apply(ReqDnsimple.Registrar, operation, [
               client(status, %{"data" => data}),
               0,
               "",
               0
             ])

    assert_request(method, "/v2/0/registrar/domains//#{resource}/0")
    refute_received {:request, _request}
  end

  defp assert_job_invalid_paths(operation) do
    {_method, _resource, [status | _], data, _type} = job_contract(operation)
    req = client(status, %{"data" => data})

    for args <- [
          ["1010", "example.com", data["id"]],
          [nil, "example.com", data["id"]],
          [1010, nil, data["id"]],
          [1010, 100, data["id"]],
          [1010, [], data["id"]],
          [1010, "example.com", nil],
          [1010, "example.com", "361"],
          [1010, "example.com", 1.5]
        ] do
      assert {:error, %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
               apply(ReqDnsimple.Registrar, operation, [req | args])
    end

    refute_received {:request, _request}
  end

  defp assert_job_malformed_success(operation) do
    {method, resource, statuses, data, _type} = job_contract(operation)
    path = "/v2/1010/registrar/domains/example.com/#{resource}/#{data["id"]}"
    required_keys = data |> Map.delete("status_description") |> Map.keys()

    invalid_data =
      Enum.map(required_keys, &Map.delete(data, &1)) ++
        for {key, value} <- [
              {"id", "361"},
              {"domain_id", nil},
              {"registrant_id", "2715"},
              {"period", 0},
              {"state", "unknown"},
              {"auto_renew", nil},
              {"whois_privacy", "false"},
              {"trustee", 0},
              {"status_description", 123},
              {"created_at", "not-a-timestamp"},
              {"updated_at", nil}
            ],
            Map.has_key?(data, key),
            do: Map.put(data, key, value)

    bodies =
      [%{}, %{"data" => nil}, %{"data" => []}, %{"data" => %{}}] ++
        Enum.map(invalid_data, &%{"data" => &1})

    for status <- statuses, body <- bodies do
      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: ^status, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: ^status}
              }} =
               apply(ReqDnsimple.Registrar, operation, [
                 client(status, body),
                 1010,
                 "example.com",
                 data["id"]
               ])

      assert_request(method, path)
      refute_received {:request, _request}
    end

    for status <- [200, 201, 202, 204] -- statuses do
      body = %{"data" => data}

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: ^status, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: ^status}
              }} =
               apply(ReqDnsimple.Registrar, operation, [
                 client(status, body),
                 1010,
                 "example.com",
                 data["id"]
               ])

      assert_request(method, path)
      refute_received {:request, _request}
    end
  end

  defp assert_job_failures(operation) do
    {method, resource, _statuses, data, _type} = job_contract(operation)

    assert_registrar_failures(
      operation,
      [1010, "example.com", data["id"]],
      method,
      "/v2/1010/registrar/domains/example.com/#{resource}/#{data["id"]}"
    )
  end

  defp assert_job_scope(operation) do
    {method, resource, [status | _], data, type} = job_contract(operation)

    assert {:ok, {result, %ReqDnsimple.Metadata{}}} =
             apply(ReqDnsimple.Registrar, operation, [
               configured_client(status, %{"data" => data}),
               "example.com",
               data["id"]
             ])

    assert result.__struct__ == type
    assert result.id == data["id"]

    assert_configured_request(
      method,
      "/v2/1010/registrar/domains/example.com/#{resource}/#{data["id"]}"
    )

    assert {:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}} =
             apply(ReqDnsimple.Registrar, operation, [unreachable_unscoped_client(), nil, nil])
  end

  defp assert_registrar_failures(operation, args, method, path, request_body \\ nil) do
    for status <- [400, 401, 402, 403, 404, 412, 422, 429, 500, 418] do
      body = %{
        "message" => "Fake offline request failure",
        "errors" => %{"base" => ["cannot complete this operation"]}
      }

      req = client(status, body) |> Req.merge(retry: :transient)

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: ^status, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: ^status}
              }} =
               apply(ReqDnsimple.Registrar, operation, [req | args])

      assert_request(method, path, %{}, request_body)
      refute_received {:request, _request}
    end

    assert {:error,
            %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
             apply(ReqDnsimple.Registrar, operation, [transport_error_client(:timeout) | args])

    refute_received {:request, _request}
  end

  defp configured_client(status, body) do
    client(status, body)
    |> Req.merge(
      base_url: "https://offline.example/v2",
      receive_timeout: 1234,
      headers: [{"x-contract", "preserved"}],
      retry: :transient
    )
    |> ReqDnsimple.Client.for_account(1010)
  end

  defp assert_configured_request(method, path, body \\ nil) do
    assert_receive {:request, request}
    assert request.method == method
    assert request.url.host == "offline.example"
    assert request.url.path == path
    assert request.options[:receive_timeout] == 1234
    assert request.options[:retry] == false
    assert Req.Request.get_header(request, "x-contract") == ["preserved"]

    assert Req.Request.get_header(request, "authorization") == [
             "Bearer dnsimple_u_fake-token"
           ]

    if body do
      assert Jason.decode!(request.body) == body
    else
      assert request.body in [nil, ""]
    end

    refute_received {:request, _request}
  end

  defp unreachable_unscoped_client do
    Req.new(
      auth: fn -> flunk("missing scope must be rejected before authentication") end,
      adapter: fn _request -> flunk("missing scope must be rejected before HTTP") end
    )
  end

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
              {%ReqDnsimple.Registrar.CheckResult{
                 domain: "example.test",
                 available: true,
                 premium: true,
                 trustee: true
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.check(client(200, body), 1010, "example.test")

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
              {%ReqDnsimple.Registrar.CheckResult{
                 domain: "",
                 available: false,
                 premium: false,
                 trustee: nil
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.check(client(200, body), 0, "")

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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 429, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 429, retry_after: "60"}
              }} =
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

      assert {:ok, {%ReqDnsimple.Registrar.CheckResult{}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.check(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "authorize_transfer_out/3" do
    test "authorizeDomainTransferOut sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
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
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Registrar.authorize_transfer_out(client(204, nil), 0, "")

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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.authorize_transfer_out(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "disable_auto_renewal/3" do
    test "disableDomainAutoRenewal sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
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
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 500, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 500}
              }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.disable_auto_renewal(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "enable_auto_renewal/3" do
    test "enableDomainAutoRenewal sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
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
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 500, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 500}
              }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.enable_auto_renewal(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "enable_whois_privacy/3" do
    test "enableWhoisPrivacy accepts the official newly-created null privacy response" do
      body = %{
        "data" => %{
          "id" => 1,
          "domain_id" => 2,
          "expires_on" => nil,
          "enabled" => nil,
          "created_at" => "2016-02-13T14:34:50Z",
          "updated_at" => "2016-02-13T14:34:50Z"
        }
      }

      assert {:ok,
              {%ReqDnsimple.Registrar.WhoisPrivacy{
                 id: 1,
                 domain_id: 2,
                 enabled: nil,
                 expires_on: nil,
                 created_at: ~U[2016-02-13 14:34:50Z],
                 updated_at: ~U[2016-02-13 14:34:50Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.enable_whois_privacy(
                 client(201, body),
                 1010,
                 "example.com"
               )

      assert_request(:put, "/v2/1010/registrar/domains/example.com/whois_privacy", %{}, nil)
      refute_received {:request, _request}
    end

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
                {%ReqDnsimple.Registrar.WhoisPrivacy{
                   id: 1,
                   domain_id: 100,
                   enabled: true,
                   expires_on: ~D[2026-09-01],
                   created_at: ~U[2026-09-01 08:00:00Z],
                   updated_at: ~U[2026-09-01 08:01:00Z]
                 }, %ReqDnsimple.Metadata{}}} =
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
        assert {:ok,
                {%ReqDnsimple.Registrar.WhoisPrivacy{enabled: false}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
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

    test "enableWhoisPrivacy disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 500, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 500}
              }} =
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
        %{"data" => Map.put(valid_data, "expires_on", 1)},
        %{"data" => Map.put(valid_data, "expires_on", "not-a-date")},
        %{"data" => Map.put(valid_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(valid_data, "updated_at", 0)}
      ]

      for status <- [200, 201], body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
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

    test "enableWhoisPrivacy preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.enable_whois_privacy(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "disable_whois_privacy/3" do
    test "disableWhoisPrivacy preserves nullable privacy fields" do
      for enabled <- [false, nil] do
        body = %{
          "data" => %{
            "id" => 1,
            "domain_id" => 2,
            "enabled" => enabled,
            "expires_on" => nil,
            "created_at" => "2016-02-13T14:34:50Z",
            "updated_at" => "2016-02-13T14:34:50Z"
          }
        }

        assert {:ok,
                {%ReqDnsimple.Registrar.WhoisPrivacy{
                   enabled: ^enabled,
                   expires_on: nil
                 }, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Registrar.disable_whois_privacy(
                   client(200, body),
                   1010,
                   "example.com"
                 )

        assert_request(:delete, "/v2/1010/registrar/domains/example.com/whois_privacy", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "disableWhoisPrivacy sends one bodyless DELETE and returns the typed 200 payload" do
      body = %{
        "data" => %{
          "id" => 1,
          "domain_id" => 100,
          "enabled" => false,
          "expires_on" => "2026-09-01",
          "created_at" => "2026-09-01T10:00:00+02:00",
          "updated_at" => "2026-09-01T10:01:00+02:00"
        }
      }

      assert {:ok,
              {%ReqDnsimple.Registrar.WhoisPrivacy{
                 id: 1,
                 domain_id: 100,
                 enabled: false,
                 expires_on: ~D[2026-09-01],
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:01:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.disable_whois_privacy(
                 client(200, body),
                 1010,
                 "example.test"
               )

      assert_request(
        :delete,
        "/v2/1010/registrar/domains/example.test/whois_privacy",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "disableWhoisPrivacy accepts integer, zero, and empty identifiers" do
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
        assert {:ok,
                {%ReqDnsimple.Registrar.WhoisPrivacy{enabled: false}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Registrar.disable_whois_privacy(
                   client(200, body),
                   account_id,
                   domain
                 )

        assert_request(
          :delete,
          "/v2/#{account_id}/registrar/domains/#{domain}/whois_privacy",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "disableWhoisPrivacy rejects invalid path parameters before HTTP" do
      request =
        client(200, %{
          "data" => %{
            "id" => 1,
            "domain_id" => 100,
            "enabled" => false,
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.disable_whois_privacy(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "disableWhoisPrivacy preserves documented and shared HTTP failures" do
      for status <- [400, 404, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"whois_privacy" => ["cannot be disabled"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Registrar.disable_whois_privacy(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :delete,
          "/v2/1010/registrar/domains/example.test/whois_privacy",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "disableWhoisPrivacy disables retries for the mutation" do
      body = %{"message" => "Fake offline request failure"}
      request = client(500, body) |> Req.merge(retry: :transient)

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 500, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 500}
              }} =
               ReqDnsimple.Registrar.disable_whois_privacy(request, 1010, "example.test")

      assert_request(
        :delete,
        "/v2/1010/registrar/domains/example.test/whois_privacy",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "disableWhoisPrivacy returns explicit errors for malformed successful responses" do
      valid_data = %{
        "id" => 1,
        "domain_id" => 100,
        "enabled" => false,
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
        %{"data" => Map.put(valid_data, "enabled", "false")},
        %{"data" => Map.put(valid_data, "expires_on", 1)},
        %{"data" => Map.put(valid_data, "expires_on", "not-a-date")},
        %{"data" => Map.put(valid_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(valid_data, "updated_at", 0)}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Registrar.disable_whois_privacy(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :delete,
          "/v2/1010/registrar/domains/example.test/whois_privacy",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "disableWhoisPrivacy preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.disable_whois_privacy(
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
              {%ReqDnsimple.Registrar.Registration{
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
               }, %ReqDnsimple.Metadata{}}} =
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

      assert {:ok,
              {%ReqDnsimple.Registrar.Registration{state: "registering", period: 10},
               %ReqDnsimple.Metadata{}}} =
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

        assert {:ok,
                {%ReqDnsimple.Registrar.Registration{state: ^state}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.register(request, account_id, domain_name, attrs)
      end

      refute_received {:request, _request}
    end

    test "registerDomain rejects malformed keyword containers before HTTP" do
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

      for attrs <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.register(request, 1010, "example.test", attrs)

        refute_received {:request, _request}
      end

      assert {:ok, {%ReqDnsimple.Registrar.Registration{}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.register(
                 request,
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

    test "registerDomain rejects explicit null extended attributes before HTTP" do
      request = client(201, %{"data" => %{}})

      assert {:error, %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
               ReqDnsimple.Registrar.register(
                 request,
                 1010,
                 "example.test",
                 registrant_id: 11,
                 extended_attributes: nil
               )

      refute_received {:request, _request}
    end

    test "registerDomain rejects struct extended attributes before HTTP" do
      request = client(201, %{"data" => %{}})

      assert {:error, %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
               ReqDnsimple.Registrar.register(
                 request,
                 1010,
                 "example.test",
                 registrant_id: 11,
                 extended_attributes: URI.parse("https://example.invalid")
               )

      refute_received {:request, _request}
    end

    test "registerDomain preserves documented and shared HTTP failures" do
      for status <- [400, 402, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"premium_price" => ["does not match"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 500, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 500}
              }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
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
              {%ReqDnsimple.Registrar.Transfer{
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
               }, %ReqDnsimple.Metadata{}}} =
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
              {%ReqDnsimple.Registrar.Transfer{
                 state: "transferring",
                 registrant_id: 0,
                 status_description: nil
               }, %ReqDnsimple.Metadata{}}} =
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
                {%ReqDnsimple.Registrar.Transfer{
                   state: ^state,
                   status_description: ""
                 }, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.transfer(request, account_id, domain_name, attrs)
      end

      refute_received {:request, _request}
    end

    test "transferDomain rejects malformed keyword attribute containers before HTTP" do
      request = client(201, %{"data" => %{}})

      for attrs <- [[:invalid], [{:registrant_id}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.transfer(request, 1010, "example.test", attrs)
      end

      refute_received {:request, _request}
    end

    test "transferDomain rejects explicit null extended attributes before HTTP" do
      request = client(201, %{"data" => %{}})

      assert {:error, %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
               ReqDnsimple.Registrar.transfer(
                 request,
                 1010,
                 "example.test",
                 registrant_id: 11,
                 extended_attributes: nil
               )

      refute_received {:request, _request}
    end

    test "transferDomain rejects struct extended attributes before HTTP" do
      request = client(201, %{"data" => %{}})

      assert {:error, %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
               ReqDnsimple.Registrar.transfer(
                 request,
                 1010,
                 "example.test",
                 registrant_id: 11,
                 extended_attributes: URI.parse("https://example.invalid")
               )

      refute_received {:request, _request}
    end

    test "transferDomain preserves documented and shared HTTP failures" do
      for status <- [400, 402, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"premium_price" => ["does not match"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 500, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 500}
              }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
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
              {%ReqDnsimple.Registrar.Renewal{
                 id: 1,
                 domain_id: 100,
                 period: 2,
                 state: "renewed",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:01:00Z]
               }, %ReqDnsimple.Metadata{}}} =
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

      assert {:ok, {%ReqDnsimple.Registrar.Renewal{state: "renewing"}, %ReqDnsimple.Metadata{}}} =
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

      assert {:ok, {%ReqDnsimple.Registrar.Renewal{state: "new"}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.renew(request, account_id, domain_name, attrs)
      end

      refute_received {:request, _request}
    end

    test "domainRenew rejects malformed keyword containers before HTTP" do
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

      for attrs <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.renew(request, 1010, "example.test", attrs)

        refute_received {:request, _request}
      end

      assert {:ok, {%ReqDnsimple.Registrar.Renewal{}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.renew(request, 1010, "example.test", [])

      assert_request(:post, "/v2/1010/registrar/domains/example.test/renewals", %{}, nil)
      refute_received {:request, _request}
    end

    test "domainRenew preserves documented and shared HTTP failures" do
      for status <- [400, 402, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"premium_price" => ["does not match"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 500, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 500}
              }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
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
              {%ReqDnsimple.Registrar.Restore{
                 id: 1,
                 domain_id: 100,
                 state: "restored",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:01:00Z]
               }, %ReqDnsimple.Metadata{}}} =
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

      assert {:ok, {%ReqDnsimple.Registrar.Restore{state: "restoring"}, %ReqDnsimple.Metadata{}}} =
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

        assert {:ok, {%ReqDnsimple.Registrar.Restore{state: ^state}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.restore(request, account_id, domain_name, attrs)
      end

      refute_received {:request, _request}
    end

    test "domainRestore rejects malformed keyword containers before HTTP" do
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

      for attrs <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.restore(request, 1010, "example.test", attrs)

        refute_received {:request, _request}
      end

      assert {:ok, {%ReqDnsimple.Registrar.Restore{}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.restore(request, 1010, "example.test", [])

      assert_request(:post, "/v2/1010/registrar/domains/example.test/restores", %{}, nil)
      refute_received {:request, _request}
    end

    test "domainRestore preserves documented and shared HTTP failures" do
      for status <- [400, 402, 404, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"premium_price" => ["does not match"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 500, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 500}
              }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
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
              {%ReqDnsimple.Registrar.Prices{
                 domain: "example.test",
                 premium: true,
                 registration_price: 20.0,
                 renewal_price: 21.0,
                 transfer_price: 22.0,
                 restore_price: 109.0,
                 trustee_price: 3.0
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.get_prices(client(200, body), 1010, "example.test")

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
              {%ReqDnsimple.Registrar.Prices{
                 domain: "",
                 premium: false,
                 registration_price: 0,
                 renewal_price: ^zero_float,
                 transfer_price: nil,
                 restore_price: 0,
                 trustee_price: nil
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.get_prices(client(200, body), 0, "")

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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
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

      assert {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: true}, %ReqDnsimple.Metadata{}}} =
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
      assert {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: false}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.get_transfer_lock(
                 client(200, %{"data" => %{"enabled" => false}}),
                 0,
                 42
               )

      assert_request(:get, "/v2/0/registrar/domains/42/transfer_lock", %{}, nil)
      refute_received {:request, _request}

      assert {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: false}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.get_transfer_lock(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "enable_transfer_lock/3" do
    test "enableDomainTransferLock sends one bodyless request and returns typed enabled state" do
      body = %{"data" => %{"enabled" => true, "ignored" => "field"}}

      assert {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: true}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.enable_transfer_lock(
                 client(201, body),
                 1010,
                 "example.test"
               )

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/transfer_lock",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "enableDomainTransferLock preserves false and accepts integer, zero, and empty identifiers" do
      request = client(201, %{"data" => %{"enabled" => false}})

      assert {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: false}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.enable_transfer_lock(request, 0, 42)

      assert_request(:post, "/v2/0/registrar/domains/42/transfer_lock", %{}, nil)
      refute_received {:request, _request}

      assert {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: false}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.enable_transfer_lock(request, 1010, "")

      assert_request(:post, "/v2/1010/registrar/domains//transfer_lock", %{}, nil)
      refute_received {:request, _request}
    end

    test "enableDomainTransferLock rejects invalid path parameters before HTTP" do
      request = client(201, %{"data" => %{"enabled" => true}})

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.0},
            {1010, []}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.enable_transfer_lock(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "enableDomainTransferLock preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["is unavailable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Registrar.enable_transfer_lock(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/transfer_lock",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "enableDomainTransferLock returns explicit errors for malformed success" do
      for body <- [
            %{},
            %{"data" => nil},
            %{"data" => %{}},
            %{"data" => %{"enabled" => nil}},
            %{"data" => %{"enabled" => "true"}},
            %{"data" => %{"enabled" => 1}}
          ] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 201, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 201}
                }} =
                 ReqDnsimple.Registrar.enable_transfer_lock(
                   client(201, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/transfer_lock",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "enableDomainTransferLock preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.enable_transfer_lock(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "disable_transfer_lock/3" do
    test "disableDomainTransferLock sends one bodyless request and returns typed disabled state" do
      body = %{"data" => %{"enabled" => false, "ignored" => "field"}}

      assert {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: false}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.disable_transfer_lock(
                 client(200, body),
                 1010,
                 "example.test"
               )

      assert_request(
        :delete,
        "/v2/1010/registrar/domains/example.test/transfer_lock",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "disableDomainTransferLock accepts integer, zero, and empty identifiers" do
      request = client(200, %{"data" => %{"enabled" => false}})

      assert {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: false}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.disable_transfer_lock(request, 0, 42)

      assert_request(:delete, "/v2/0/registrar/domains/42/transfer_lock", %{}, nil)
      refute_received {:request, _request}

      assert {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: false}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.disable_transfer_lock(request, 1010, "")

      assert_request(:delete, "/v2/1010/registrar/domains//transfer_lock", %{}, nil)
      refute_received {:request, _request}
    end

    test "disableDomainTransferLock rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => %{"enabled" => false}})

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.0},
            {1010, []}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.disable_transfer_lock(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "disableDomainTransferLock preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["is unavailable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Registrar.disable_transfer_lock(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :delete,
          "/v2/1010/registrar/domains/example.test/transfer_lock",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "disableDomainTransferLock returns explicit errors for malformed success" do
      for body <- [
            %{},
            %{"data" => nil},
            %{"data" => %{}},
            %{"data" => %{"enabled" => nil}},
            %{"data" => %{"enabled" => "false"}},
            %{"data" => %{"enabled" => 0}}
          ] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Registrar.disable_transfer_lock(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :delete,
          "/v2/1010/registrar/domains/example.test/transfer_lock",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "disableDomainTransferLock preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.disable_transfer_lock(
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

      assert {:ok, {^name_servers, %ReqDnsimple.Metadata{}}} =
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
      assert {:ok, {[], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.get_delegation(client(200, %{"data" => []}), 0, 42)

      assert_request(:get, "/v2/0/registrar/domains/42/delegation", %{}, nil)
      refute_received {:request, _request}

      assert {:ok, {[], %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
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

      assert {:ok, {^name_servers, %ReqDnsimple.Metadata{}}} =
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
      assert {:ok, {[], %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.change_delegation(
                   request,
                   account_id,
                   domain,
                   attrs
                 )
      end

      refute_received {:request, _request}
    end

    test "changeDomainDelegation rejects malformed keyword containers before HTTP" do
      request = client(200, %{"data" => []})

      assert {:ok, {[], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Registrar.change_delegation(
                 request,
                 1010,
                 "example.test",
                 name_servers: []
               )

      assert_request(:put, "/v2/1010/registrar/domains/example.test/delegation", %{}, [])
      refute_received {:request, _request}

      for attrs <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Registrar.change_delegation(
                   request,
                   1010,
                   "example.test",
                   attrs
                 )

        refute_received {:request, _request}
      end
    end

    test "changeDomainDelegation preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"name_servers" => ["is invalid"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 500, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 500}
              }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Registrar.change_delegation(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 name_servers: ["ns1.example.test"]
               )
    end
  end
end
