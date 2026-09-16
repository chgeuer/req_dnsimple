defmodule ReqDnsimple.RegistrantChangeTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @registrant_change_data %{
    "id" => 1,
    "account_id" => 1010,
    "contact_id" => 11,
    "domain_id" => 100,
    "state" => "pending",
    "extended_attributes" => %{"x-fi-registrant-idnumber" => "fake-offline-id"},
    "registry_owner_change" => true,
    "irt_lock_lifted_by" => nil,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  @pagination %{
    "current_page" => 1,
    "per_page" => 1,
    "total_entries" => 1,
    "total_pages" => 1
  }

  @check_data %{
    "domain_id" => 101,
    "contact_id" => 101,
    "extended_attributes" => [],
    "registry_owner_change" => true
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
    test "every registrant-change operation, alias and scoped overload preserves HTTP metadata" do
      contracts = [
        {:check, [1010, [domain_id: 101, contact_id: 101]], 200, %{"data" => @check_data}},
        {:create, [1010, [domain_id: 100, contact_id: 11]], 201,
         %{"data" => @registrant_change_data}},
        {:create, [1010, [domain_id: 100, contact_id: 11]], 202,
         %{"data" => @registrant_change_data}},
        {:get, [1010, 1], 200, %{"data" => @registrant_change_data}},
        {:list_page, [1010, []], 200,
         %{"data" => [@registrant_change_data], "pagination" => @pagination}},
        {:list, [1010, []], 200,
         %{"data" => [@registrant_change_data], "pagination" => @pagination}},
        {:cancel, [1010, 1], 202, %{"data" => @registrant_change_data}},
        {:cancel, [1010, 1], 204, nil}
      ]

      for {operation, args, status, body} <- contracts,
          scoped? <- [false, true],
          {http_status, response_body} <- [
            {status, body},
            {404, %{"message" => "Offline resource not found"}}
          ] do
        req = client(http_status, response_body, self(), @response_headers)
        req = if scoped?, do: ReqDnsimple.Client.for_account(req, 1010), else: req
        call_args = if scoped?, do: tl(args), else: args

        expected_metadata = %{
          @response_metadata
          | status: http_status,
            pagination: get_in(response_body, ["pagination"])
        }

        if http_status == 404 do
          assert {:error,
                  %ReqDnsimple.Error{
                    reason: %{status: 404, response: ^response_body},
                    metadata: ^expected_metadata
                  }} = apply(ReqDnsimple.RegistrantChange, operation, [req | call_args])
        else
          assert {:ok, {result, %ReqDnsimple.Metadata{} = metadata}} =
                   apply(ReqDnsimple.RegistrantChange, operation, [req | call_args])

          assert metadata == expected_metadata
          assert is_nil(result) == (status == 204)
        end

        assert_receive {:request, %Req.Request{}}
        refute_received {:request, _request}
      end
    end

    test "malformed headers do not discard valid registrant-change data" do
      assert {:ok,
              {%ReqDnsimple.RegistrantChange{id: 1},
               %ReqDnsimple.Metadata{
                 status: 202,
                 rate_limit: nil,
                 rate_limit_remaining: 7,
                 parse_errors: %{rate_limit: {:invalid_header, ["invalid"]}}
               }}} =
               ReqDnsimple.RegistrantChange.create(
                 client(202, %{"data" => @registrant_change_data}, self(),
                   "x-ratelimit-limit": "invalid",
                   "x-ratelimit-remaining": "7"
                 ),
                 1010,
                 domain_id: 100,
                 contact_id: 11
               )

      assert_request(:post, "/v2/1010/registrar/registrant_changes", %{}, %{
        "domain_id" => 100,
        "contact_id" => 11
      })
    end

    test "list aliases retain valid data independently of pagination metadata" do
      incomplete = Map.delete(@pagination, "total_entries")
      malformed = %{@pagination | "current_page" => "1"}
      zero_size = %{@pagination | "per_page" => 0}
      extended = Map.put(@pagination, "cursor", "opaque-cursor")

      cases = [
        {%{}, nil, %{}},
        {%{"pagination" => nil}, nil, %{}},
        {%{"pagination" => incomplete}, nil, %{pagination: {:invalid_pagination, incomplete}}},
        {%{"pagination" => malformed}, nil, %{pagination: {:invalid_pagination, malformed}}},
        {%{"pagination" => zero_size}, zero_size, %{}},
        {%{"pagination" => extended}, extended, %{}}
      ]

      for {extra, pagination, parse_errors} <- cases,
          operation <- [:list_page, :list] do
        body = Map.merge(%{"data" => [@registrant_change_data]}, extra)

        assert {:ok,
                {[%ReqDnsimple.RegistrantChange{id: 1}],
                 %ReqDnsimple.Metadata{
                   status: 200,
                   pagination: ^pagination,
                   pages: [],
                   parse_errors: ^parse_errors
                 }}} =
                 apply(ReqDnsimple.RegistrantChange, operation, [client(200, body), 1010, []])

        assert_request(:get, "/v2/1010/registrar/registrant_changes")
        refute_received {:request, _request}
      end
    end

    test "list_all retains ordered page metadata and latest response budgets for both scopes" do
      first_page = %{@pagination | "total_entries" => 2, "total_pages" => 2}
      second_page = %{first_page | "current_page" => 2}

      for scoped? <- [false, true] do
        req =
          response_client(fn page ->
            pagination = if page == 1, do: first_page, else: second_page

            {200,
             %{
               "data" => [Map.put(@registrant_change_data, "id", page)],
               "pagination" => pagination
             },
             [
               {"x-ratelimit-limit", "2400"},
               {"x-ratelimit-remaining", to_string(2400 - page)},
               {"x-ratelimit-reset", to_string(1_790_000_000 + page)},
               {"x-request-id", "page-#{page}"},
               {"etag", "\"page-#{page}\""},
               {"retry-after", to_string(page)}
             ]}
          end)

        result =
          if scoped? do
            req
            |> ReqDnsimple.Client.for_account(1010)
            |> ReqDnsimple.RegistrantChange.list_all(per_page: 1)
          else
            ReqDnsimple.RegistrantChange.list_all(req, 1010, per_page: 1)
          end

        assert {:ok,
                {[%ReqDnsimple.RegistrantChange{id: 1}, %ReqDnsimple.RegistrantChange{id: 2}],
                 %ReqDnsimple.Metadata{
                   status: nil,
                   pagination: nil,
                   request_id: nil,
                   etag: nil,
                   rate_limit: 2400,
                   rate_limit_remaining: 2398,
                   rate_limit_reset: 1_790_000_002,
                   retry_after: "2",
                   pages: [
                     %ReqDnsimple.Metadata{
                       status: 200,
                       pagination: ^first_page,
                       rate_limit: 2400,
                       rate_limit_remaining: 2399,
                       rate_limit_reset: 1_790_000_001,
                       request_id: "page-1",
                       etag: "\"page-1\"",
                       retry_after: "1",
                       pages: [],
                       parse_errors: %{}
                     },
                     %ReqDnsimple.Metadata{
                       status: 200,
                       pagination: ^second_page,
                       rate_limit: 2400,
                       rate_limit_remaining: 2398,
                       rate_limit_reset: 1_790_000_002,
                       request_id: "page-2",
                       etag: "\"page-2\"",
                       retry_after: "2",
                       pages: [],
                       parse_errors: %{}
                     }
                   ],
                   parse_errors: %{}
                 }}} = result

        for page <- [1, 2] do
          assert_request(
            :get,
            "/v2/1010/registrar/registrant_changes",
            %{"page" => page, "per_page" => 1}
          )
        end

        refute_received {:request, _request}
      end
    end

    test "list_all retains completed page metadata after a transport failure" do
      first_page = %{@pagination | "total_entries" => 2, "total_pages" => 2}
      page_metadata = %{@response_metadata | status: 200, pagination: first_page}

      expected_metadata = %{
        @response_metadata
        | pages: [page_metadata],
          request_id: nil,
          etag: nil
      }

      req =
        response_client(fn
          1 ->
            {200, %{"data" => [@registrant_change_data], "pagination" => first_page},
             @response_headers}

          2 ->
            {:error, :timeout}
        end)

      assert {:error,
              %ReqDnsimple.Error{
                reason: %Req.TransportError{reason: :timeout},
                metadata: ^expected_metadata
              }} = ReqDnsimple.RegistrantChange.list_all(req, 1010)

      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 1})
      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "check/3" do
    test "checkRegistrantChange sends the root attributes and returns the official check fixture" do
      assert {:ok,
              {%ReqDnsimple.RegistrantChange.CheckResult{
                 domain_id: 101,
                 contact_id: 101,
                 extended_attributes: [],
                 registry_owner_change: true
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.check(
                 client(200, %{"data" => @check_data}),
                 1010,
                 domain_id: "example.com",
                 contact_id: "101"
               )

      assert_request(
        :post,
        "/v2/1010/registrar/registrant_changes/check",
        %{},
        %{domain_id: "example.com", contact_id: "101"}
      )

      refute_received {:request, _request}
    end

    test "checkRegistrantChange preserves IDs, false flags and complete attribute definitions" do
      definitions = [
        %{
          "name" => "fake-registry-attribute",
          "description" => "Offline registry requirement",
          "required" => false,
          "options" => [%{"value" => "person", "label" => "Person"}]
        },
        %{"name" => "another-offline-requirement", "required" => true}
      ]

      data = %{
        "domain_id" => 0,
        "contact_id" => 0,
        "extended_attributes" => definitions,
        "registry_owner_change" => false
      }

      for attrs <- [
            [domain_id: 0, contact_id: 0],
            [domain_id: "", contact_id: ""],
            [domain_id: 101, contact_id: "101"]
          ] do
        assert {:ok,
                {%ReqDnsimple.RegistrantChange.CheckResult{
                   domain_id: 0,
                   contact_id: 0,
                   extended_attributes: ^definitions,
                   registry_owner_change: false
                 }, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.RegistrantChange.check(client(200, %{"data" => data}), 0, attrs)

        assert_request(:post, "/v2/0/registrar/registrant_changes/check", %{}, Map.new(attrs))
        refute_received {:request, _request}
      end
    end

    test "checkRegistrantChange rejects invalid paths and malformed keyword attributes before HTTP" do
      req = client(200, %{"data" => @check_data})

      for {account_id, attrs} <- [
            {"1010", [domain_id: 101, contact_id: 101]},
            {nil, [domain_id: 101, contact_id: 101]},
            {1010, []},
            {1010, nil},
            {1010, %{domain_id: 101, contact_id: 101}},
            {1010, [:invalid]},
            {1010, [{:domain_id}]},
            {1010, [{:domain_id, 101} | :invalid]},
            {1010, [domain_id: 101]},
            {1010, [contact_id: 101]},
            {1010, [domain_id: nil, contact_id: 101]},
            {1010, [domain_id: [], contact_id: 101]},
            {1010, [domain_id: 101, contact_id: nil]},
            {1010, [domain_id: 101, contact_id: 1.5]},
            {1010, [domain_id: 101, contact_id: 101, extended_attributes: %{}]},
            {1010, [domain_id: 101, contact_id: 101, unknown: true]}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.RegistrantChange.check(req, account_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "checkRegistrantChange rejects malformed success bodies and statuses" do
      invalid_data =
        Enum.map(Map.keys(@check_data), &Map.delete(@check_data, &1)) ++
          Enum.map(
            [
              {"domain_id", "101"},
              {"contact_id", nil},
              {"extended_attributes", %{}},
              {"extended_attributes", [nil]},
              {"extended_attributes", [%{"name" => "valid"}, "invalid"]},
              {"registry_owner_change", 0}
            ],
            fn {key, value} -> Map.put(@check_data, key, value) end
          )

      bodies =
        [%{}, %{"data" => nil}, %{"data" => []}, %{"data" => %{}}] ++
          Enum.map(invalid_data, &%{"data" => &1})

      for body <- bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.RegistrantChange.check(
                   client(200, body),
                   1010,
                   domain_id: 101,
                   contact_id: 101
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/registrant_changes/check",
          %{},
          %{domain_id: 101, contact_id: 101}
        )

        refute_received {:request, _request}
      end

      for status <- [201, 202, 204] do
        body = %{"data" => @check_data}

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.RegistrantChange.check(
                   client(status, body),
                   1010,
                   domain_id: 101,
                   contact_id: 101
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/registrant_changes/check",
          %{},
          %{domain_id: 101, contact_id: 101}
        )

        refute_received {:request, _request}
      end
    end

    test "checkRegistrantChange preserves HTTP failures and disables caller-requested retries" do
      for status <- [400, 401, 403, 404, 422, 429, 500, 418] do
        body = %{
          "message" => "Fake offline check failure",
          "errors" => %{"contact_id" => ["cannot change registrant"]}
        }

        req = client(status, body) |> Req.merge(retry: :transient)

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.RegistrantChange.check(req, 1010, domain_id: 101, contact_id: 101)

        assert_request(
          :post,
          "/v2/1010/registrar/registrant_changes/check",
          %{},
          %{domain_id: 101, contact_id: 101}
        )

        refute_received {:request, _request}
      end
    end

    test "checkRegistrantChange preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.RegistrantChange.check(
                 transport_error_client(:timeout),
                 1010,
                 domain_id: 101,
                 contact_id: 101
               )
    end

    test "checkRegistrantChange scoped wrapper preserves caller configuration" do
      req =
        client(200, %{"data" => @check_data})
        |> Req.merge(
          base_url: "https://offline.example/v2",
          receive_timeout: 1234,
          headers: [{"x-contract", "preserved"}],
          retry: :transient
        )
        |> ReqDnsimple.Client.for_account(1010)

      assert {:ok,
              {%ReqDnsimple.RegistrantChange.CheckResult{domain_id: 101, contact_id: 101},
               %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.check(req, domain_id: "example.com", contact_id: 101)

      assert_receive {:request, request}
      assert request.method == :post
      assert request.url.host == "offline.example"
      assert request.url.path == "/v2/1010/registrar/registrant_changes/check"
      assert request.options[:receive_timeout] == 1234
      assert request.options[:retry] == false
      assert Req.Request.get_header(request, "x-contract") == ["preserved"]
      assert Req.Request.get_header(request, "authorization") == ["Bearer dnsimple_u_fake-token"]
      assert Jason.decode!(request.body) == %{"domain_id" => "example.com", "contact_id" => 101}
      refute_received {:request, _request}
    end

    test "checkRegistrantChange rejects missing scope before validation, authentication and HTTP" do
      req =
        Req.new(
          auth: fn -> flunk("missing scope must be rejected before authentication") end,
          adapter: fn _request -> flunk("missing scope must be rejected before HTTP") end
        )

      assert {:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}} =
               ReqDnsimple.RegistrantChange.check(req, [:invalid])
    end
  end

  describe "create/3" do
    test "createRegistrantChange sends every supplied field once and returns a typed change" do
      completed_data = Map.put(@registrant_change_data, "state", "completed")

      assert {:ok,
              {%ReqDnsimple.RegistrantChange{
                 id: 1,
                 account_id: 1010,
                 contact_id: 11,
                 domain_id: 100,
                 state: "completed",
                 extended_attributes: %{
                   "x-fi-registrant-idnumber" => "fake-offline-id"
                 },
                 registry_owner_change: true,
                 irt_lock_lifted_by: nil,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.create(
                 client(201, %{"data" => completed_data}),
                 1010,
                 domain_id: "example.test",
                 contact_id: "11",
                 extended_attributes: %{
                   "x-fi-registrant-idnumber" => "fake-offline-id"
                 }
               )

      assert_request(
        :post,
        "/v2/1010/registrar/registrant_changes",
        %{},
        %{
          "domain_id" => "example.test",
          "contact_id" => "11",
          "extended_attributes" => %{
            "x-fi-registrant-idnumber" => "fake-offline-id"
          }
        }
      )

      refute_received {:request, _request}
    end

    test "createRegistrantChange accepts 202 and preserves omission, zero, empty strings and maps" do
      assert {:ok, {%ReqDnsimple.RegistrantChange{state: "pending"}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.create(
                 client(202, %{"data" => @registrant_change_data}),
                 0,
                 domain_id: "",
                 contact_id: 0
               )

      assert_request(
        :post,
        "/v2/0/registrar/registrant_changes",
        %{},
        %{"domain_id" => "", "contact_id" => 0}
      )

      assert {:ok,
              {%ReqDnsimple.RegistrantChange{extended_attributes: %{}}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.create(
                 client(201, %{
                   "data" => Map.put(@registrant_change_data, "extended_attributes", %{})
                 }),
                 1010,
                 domain_id: 100,
                 contact_id: "11",
                 extended_attributes: %{}
               )

      assert_request(
        :post,
        "/v2/1010/registrar/registrant_changes",
        %{},
        %{"domain_id" => 100, "contact_id" => "11", "extended_attributes" => %{}}
      )

      refute_received {:request, _request}
    end

    test "createRegistrantChange rejects invalid attributes before HTTP" do
      request = client(201, %{"data" => @registrant_change_data})

      for {account_id, attrs} <- [
            {"1010", [domain_id: "example.test", contact_id: 11]},
            {nil, [domain_id: "example.test", contact_id: 11]},
            {1010, [:invalid]},
            {1010, [{:domain_id}]},
            {1010, []},
            {1010, [domain_id: "example.test"]},
            {1010, [contact_id: 11]},
            {1010, [domain_id: nil, contact_id: 11]},
            {1010, [domain_id: false, contact_id: 11]},
            {1010, [domain_id: [], contact_id: 11]},
            {1010, [domain_id: "example.test", contact_id: nil]},
            {1010, [domain_id: "example.test", contact_id: false]},
            {1010, [domain_id: "example.test", contact_id: []]},
            {1010,
             [
               domain_id: "example.test",
               contact_id: 11,
               extended_attributes: nil
             ]},
            {1010,
             [
               domain_id: "example.test",
               contact_id: 11,
               extended_attributes: %{"key" => 1}
             ]},
            {1010,
             [
               domain_id: "example.test",
               contact_id: 11,
               extended_attributes: %{key: "value"}
             ]},
            {1010,
             [
               domain_id: "example.test",
               contact_id: 11,
               extended_attributes: MapSet.new()
             ]},
            {1010, [domain_id: "example.test", contact_id: 11, unknown: true]}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.RegistrantChange.create(request, account_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "createRegistrantChange preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"contact_id" => ["is invalid"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.RegistrantChange.create(
                   client(status, body),
                   1010,
                   domain_id: "example.test",
                   contact_id: 11
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/registrant_changes",
          %{},
          %{"domain_id" => "example.test", "contact_id" => 11}
        )

        refute_received {:request, _request}
      end
    end

    test "createRegistrantChange returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@registrant_change_data, "id")},
        %{"data" => Map.put(@registrant_change_data, "state", "unknown")},
        %{"data" => Map.put(@registrant_change_data, "extended_attributes", %{"key" => 1})},
        %{"data" => Map.put(@registrant_change_data, "irt_lock_lifted_by", "not-a-date")},
        %{"data" => Map.put(@registrant_change_data, "updated_at", nil)}
      ]

      for {status, body} <-
            Enum.map(malformed_payloads, &{201, &1}) ++
              [{202, %{"data" => nil}}, {200, %{"data" => @registrant_change_data}}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.RegistrantChange.create(
                   client(status, body),
                   1010,
                   domain_id: "example.test",
                   contact_id: 11
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/registrant_changes",
          %{},
          %{"domain_id" => "example.test", "contact_id" => 11}
        )

        refute_received {:request, _request}
      end
    end

    test "createRegistrantChange preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.RegistrantChange.create(
                 transport_error_client(:timeout),
                 1010,
                 domain_id: "example.test",
                 contact_id: 11
               )
    end
  end

  describe "get/3" do
    test "getRegistrantChange sends one bodyless request and returns a typed change" do
      assert {:ok,
              {%ReqDnsimple.RegistrantChange{
                 id: 1,
                 account_id: 1010,
                 contact_id: 11,
                 domain_id: 100,
                 state: "pending",
                 extended_attributes: %{
                   "x-fi-registrant-idnumber" => "fake-offline-id"
                 },
                 registry_owner_change: true,
                 irt_lock_lifted_by: nil,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.get(
                 client(200, %{"data" => @registrant_change_data}),
                 1010,
                 1
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getRegistrantChange preserves every state and valid false, zero, empty, and date values" do
      for state <- ["new", "pending", "cancelling", "cancelled", "completed"] do
        data =
          Map.merge(@registrant_change_data, %{
            "id" => 0,
            "account_id" => 0,
            "contact_id" => 0,
            "domain_id" => 0,
            "state" => state,
            "extended_attributes" => %{},
            "registry_owner_change" => false,
            "irt_lock_lifted_by" => "2026-09-02"
          })

        assert {:ok,
                {%ReqDnsimple.RegistrantChange{
                   id: 0,
                   account_id: 0,
                   contact_id: 0,
                   domain_id: 0,
                   state: ^state,
                   extended_attributes: %{},
                   registry_owner_change: false,
                   irt_lock_lifted_by: ~D[2026-09-02]
                 }, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.RegistrantChange.get(
                   client(200, %{"data" => data}),
                   0,
                   0
                 )

        assert_request(:get, "/v2/0/registrar/registrant_changes/0", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getRegistrantChange rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @registrant_change_data})

      for {account_id, registrant_change_id} <- [
            {"1010", 1},
            {nil, 1},
            {1010, "1"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.RegistrantChange.get(
                   request,
                   account_id,
                   registrant_change_id
                 )
      end

      refute_received {:request, _request}
    end

    test "getRegistrantChange preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"registrant_change" => ["is unavailable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.RegistrantChange.get(client(status, body), 1010, 1)

        assert_request(:get, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getRegistrantChange returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@registrant_change_data, "id")},
        %{"data" => Map.put(@registrant_change_data, "account_id", "1010")},
        %{"data" => Map.put(@registrant_change_data, "state", "unknown")},
        %{"data" => Map.put(@registrant_change_data, "extended_attributes", %{key: "value"})},
        %{
          "data" =>
            Map.put(
              @registrant_change_data,
              "extended_attributes",
              %{"key" => 1}
            )
        },
        %{"data" => Map.put(@registrant_change_data, "registry_owner_change", 1)},
        %{"data" => Map.put(@registrant_change_data, "irt_lock_lifted_by", "not-a-date")},
        %{"data" => Map.put(@registrant_change_data, "created_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.RegistrantChange.get(client(200, body), 1010, 1)

        assert_request(:get, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [
            {201, %{"data" => @registrant_change_data}},
            {204, nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.RegistrantChange.get(client(status, body), 1010, 1)

        assert_request(:get, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getRegistrantChange preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.RegistrantChange.get(
                 transport_error_client(:timeout),
                 1010,
                 1
               )
    end
  end

  describe "list_page/3 and list/3" do
    test "listRegistrantChanges merges inherited keyword params without crashing" do
      req =
        client(200, %{"data" => [@registrant_change_data], "pagination" => @pagination})
        |> Req.merge(params: [state: "pending", domain_id: "100"])

      assert {:ok,
              {[%ReqDnsimple.RegistrantChange{id: 1}],
               %ReqDnsimple.Metadata{pagination: @pagination}}} =
               ReqDnsimple.RegistrantChange.list_page(req, 1010, [])

      assert_request(
        :get,
        "/v2/1010/registrar/registrant_changes",
        %{"state" => "pending", "domain_id" => "100"}
      )

      refute_received {:request, _request}
    end

    test "listRegistrantChanges operation options override inherited encoded query keys" do
      req =
        client(200, %{"data" => [@registrant_change_data], "pagination" => @pagination})
        |> Req.merge(
          params: [
            {"state", "new"},
            {:state, "pending"},
            {"page", 9},
            {"per_page", 30},
            {"trace", "offline"}
          ]
        )

      assert {:ok,
              {[%ReqDnsimple.RegistrantChange{id: 1}],
               %ReqDnsimple.Metadata{pagination: @pagination}}} =
               ReqDnsimple.RegistrantChange.list_page(req, 1010,
                 state: "completed",
                 page: 1,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/registrar/registrant_changes",
        %{"state" => "completed", "page" => 1, "per_page" => 1, "trace" => "offline"}
      )

      refute_received {:request, _request}
    end

    test "listRegistrantChanges sends every filter once and returns typed changes" do
      pagination = %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}

      assert {:ok,
              {[
                 %ReqDnsimple.RegistrantChange{
                   id: 1,
                   account_id: 1010,
                   contact_id: 11,
                   domain_id: 100,
                   state: "pending",
                   extended_attributes: %{
                     "x-fi-registrant-idnumber" => "fake-offline-id"
                   },
                   registry_owner_change: true,
                   irt_lock_lifted_by: nil,
                   created_at: ~U[2026-09-01 08:00:00Z],
                   updated_at: ~U[2026-09-01 08:30:00Z]
                 }
               ], %ReqDnsimple.Metadata{pagination: ^pagination}}} =
               ReqDnsimple.RegistrantChange.list_page(
                 client(200, %{"data" => [@registrant_change_data], "pagination" => pagination}),
                 1010,
                 sort: [id: :asc, id: :desc],
                 state: "completed",
                 domain_id: "100",
                 contact_id: "11",
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/registrar/registrant_changes",
        %{
          "sort" => "id:asc,id:desc",
          "state" => "completed",
          "domain_id" => "100",
          "contact_id" => "11",
          "page" => 2,
          "per_page" => 1
        },
        nil
      )

      refute_received {:request, _request}
    end

    test "listRegistrantChanges alias preserves omitted filters, empty pages and lock dates" do
      dated = Map.put(@registrant_change_data, "irt_lock_lifted_by", "2026-09-02")

      assert {:ok,
              {[%ReqDnsimple.RegistrantChange{irt_lock_lifted_by: ~D[2026-09-02]}],
               %ReqDnsimple.Metadata{pagination: @pagination}}} =
               ReqDnsimple.RegistrantChange.list(
                 client(200, %{"data" => [dated], "pagination" => @pagination}),
                 0
               )

      assert_request(:get, "/v2/0/registrar/registrant_changes", %{}, nil)
      refute_received {:request, _request}

      empty_pagination = %{@pagination | "total_entries" => 0, "total_pages" => 0}

      assert {:ok, {[], %ReqDnsimple.Metadata{pagination: ^empty_pagination}}} =
               ReqDnsimple.RegistrantChange.list_page(
                 client(200, %{"data" => [], "pagination" => empty_pagination}),
                 1010
               )
    end

    test "listRegistrantChanges rejects invalid paths and options before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      for {account_id, opts} <- [
            {"1010", []},
            {nil, []},
            {1010, [:invalid]},
            {1010, [{:name}]},
            {1010, [unknown: true]},
            {1010, [state: nil]},
            {1010, [state: "open"]},
            {1010, [domain_id: 100]},
            {1010, [contact_id: 11]},
            {1010, [sort: [name: :asc]]},
            {1010, [sort: [id: :sideways]]},
            {1010, [page: 0]},
            {1010, [per_page: 0]},
            {1010, [per_page: 101]}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.RegistrantChange.list_page(request, account_id, opts)
      end

      refute_received {:request, _request}
    end

    test "listRegistrantChanges preserves HTTP and transport failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"state" => ["is invalid"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.RegistrantChange.list_page(client(status, body), 1010)

        assert_request(:get, "/v2/1010/registrar/registrant_changes", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.RegistrantChange.list_page(transport_error_client(:timeout), 1010)
    end

    test "listRegistrantChanges rejects malformed successful responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => @pagination},
        %{
          "data" => [Map.delete(@registrant_change_data, "irt_lock_lifted_by")],
          "pagination" => @pagination
        },
        %{
          "data" => [Map.put(@registrant_change_data, "irt_lock_lifted_by", "invalid")],
          "pagination" => @pagination
        },
        %{
          "data" => [Map.put(@registrant_change_data, "extended_attributes", %{"key" => 1})],
          "pagination" => @pagination
        }
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.RegistrantChange.list_page(client(200, body), 1010)

        assert_request(:get, "/v2/1010/registrar/registrant_changes", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  describe "list_all/3" do
    test "returns empty and one-page collections without extra requests" do
      empty_pagination = %{@pagination | "total_entries" => 0, "total_pages" => 0}

      assert {:ok, {[], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.list_all(
                 client(200, %{"data" => [], "pagination" => empty_pagination}),
                 1010
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 1})
      refute_received {:request, _request}

      assert {:ok, {[%ReqDnsimple.RegistrantChange{id: 1}], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.list_all(
                 client(200, %{"data" => [@registrant_change_data], "pagination" => @pagination}),
                 1010
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 1})
      refute_received {:request, _request}
    end

    test "enumerates from page one while preserving filters, sorting and order" do
      second = Map.merge(@registrant_change_data, %{"id" => 2, "domain_id" => 200})

      pages = %{
        1 =>
          {[@registrant_change_data],
           %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}},
        2 =>
          {[second],
           %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}}
      }

      assert {:ok,
              {[
                 %ReqDnsimple.RegistrantChange{id: 1, domain_id: 100},
                 %ReqDnsimple.RegistrantChange{id: 2, domain_id: 200}
               ], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.list_all(
                 page_client(pages),
                 1010,
                 sort: [id: :desc],
                 state: "pending",
                 domain_id: "",
                 contact_id: "",
                 per_page: 1
               )

      expected_query = %{
        "sort" => "id:desc",
        "state" => "pending",
        "domain_id" => "",
        "contact_id" => "",
        "per_page" => 1
      }

      assert_request(
        :get,
        "/v2/1010/registrar/registrant_changes",
        Map.put(expected_query, "page", 1)
      )

      assert_request(
        :get,
        "/v2/1010/registrar/registrant_changes",
        Map.put(expected_query, "page", 2)
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      assert {:error, %ReqDnsimple.Error{reason: {:invalid_option, :page}, metadata: nil}} =
               ReqDnsimple.RegistrantChange.list_all(request, 1010, page: 2)

      for opts <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.RegistrantChange.list_all(request, 1010, opts)
      end

      refute_received {:request, _request}
    end

    test "aborts on later-page failures and rejects non-progressing pagination" do
      first_page =
        %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 503, response: %{"message" => "unavailable"}},
                metadata: %ReqDnsimple.Metadata{
                  status: 503,
                  pages: [
                    %ReqDnsimple.Metadata{status: 200, pagination: ^first_page},
                    %ReqDnsimple.Metadata{status: 503}
                  ]
                }
              }} =
               ReqDnsimple.RegistrantChange.list_all(
                 response_client(fn
                   1 -> {200, %{"data" => [@registrant_change_data], "pagination" => first_page}}
                   2 -> {503, %{"message" => "unavailable"}}
                 end),
                 1010
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 1})
      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 2})

      repeated = %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      assert {:error,
              %ReqDnsimple.Error{
                reason: {:invalid_pagination, ^repeated},
                metadata: %ReqDnsimple.Metadata{
                  status: 200,
                  pages: [
                    %ReqDnsimple.Metadata{status: 200, pagination: ^repeated},
                    %ReqDnsimple.Metadata{status: 200, pagination: ^repeated}
                  ]
                }
              }} =
               ReqDnsimple.RegistrantChange.list_all(
                 response_client(fn _page ->
                   {200, %{"data" => [@registrant_change_data], "pagination" => repeated}}
                 end),
                 1010
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 1})
      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "cancel/3" do
    test "deleteRegistrantChange sends one bodyless request and returns a cancelling change" do
      data = Map.put(@registrant_change_data, "state", "cancelling")

      assert {:ok,
              {%ReqDnsimple.RegistrantChange{
                 id: 1,
                 account_id: 1010,
                 contact_id: 11,
                 domain_id: 100,
                 state: "cancelling",
                 extended_attributes: %{
                   "x-fi-registrant-idnumber" => "fake-offline-id"
                 },
                 registry_owner_change: true,
                 irt_lock_lifted_by: nil,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.cancel(
                 client(202, %{"data" => data}),
                 1010,
                 1
               )

      assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteRegistrantChange returns nil data with metadata for immediate cancellation" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.RegistrantChange.cancel(client(204, nil), 1010, 1)

      assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteRegistrantChange preserves zero values, empty attributes, false and a lock date" do
      data =
        Map.merge(@registrant_change_data, %{
          "id" => 0,
          "account_id" => 0,
          "contact_id" => 0,
          "domain_id" => 0,
          "state" => "cancelled",
          "extended_attributes" => %{},
          "registry_owner_change" => false,
          "irt_lock_lifted_by" => "2026-09-02"
        })

      assert {:ok,
              {%ReqDnsimple.RegistrantChange{
                 id: 0,
                 account_id: 0,
                 contact_id: 0,
                 domain_id: 0,
                 state: "cancelled",
                 extended_attributes: %{},
                 registry_owner_change: false,
                 irt_lock_lifted_by: ~D[2026-09-02]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.RegistrantChange.cancel(client(202, %{"data" => data}), 0, 0)

      assert_request(:delete, "/v2/0/registrar/registrant_changes/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteRegistrantChange rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, registrant_change_id} <- [
            {"1010", 1},
            {nil, 1},
            {1010, "1"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.RegistrantChange.cancel(
                   request,
                   account_id,
                   registrant_change_id
                 )
      end

      refute_received {:request, _request}
    end

    test "deleteRegistrantChange preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"registrant_change" => ["cannot be cancelled"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.RegistrantChange.cancel(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteRegistrantChange returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@registrant_change_data, "id")},
        %{"data" => Map.put(@registrant_change_data, "account_id", "1010")},
        %{"data" => Map.put(@registrant_change_data, "state", "unknown")},
        %{"data" => Map.put(@registrant_change_data, "extended_attributes", %{key: "value"})},
        %{"data" => Map.put(@registrant_change_data, "registry_owner_change", 1)},
        %{"data" => Map.put(@registrant_change_data, "irt_lock_lifted_by", "not-a-date")},
        %{"data" => Map.put(@registrant_change_data, "updated_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 202, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 202}
                }} =
                 ReqDnsimple.RegistrantChange.cancel(client(202, body), 1010, 1)

        assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [
            {200, %{"data" => @registrant_change_data}},
            {201, %{"data" => @registrant_change_data}},
            {205, nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.RegistrantChange.cancel(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteRegistrantChange preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.RegistrantChange.cancel(
                 transport_error_client(:timeout),
                 1010,
                 1
               )
    end
  end

  defp page_client(pages) do
    response_client(fn page ->
      {data, pagination} = Map.fetch!(pages, page)
      {200, %{"data" => data, "pagination" => pagination}}
    end)
  end

  defp response_client(response_for_page) do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:request, request})
      page = request.url.query |> URI.decode_query() |> Map.fetch!("page") |> String.to_integer()

      case response_for_page.(page) do
        {:error, reason} ->
          {request, %Req.TransportError{reason: reason}}

        {status, body} ->
          {request, %Req.Response{status: status, body: body}}

        {status, body, headers} ->
          {request, Req.Response.new(status: status, body: body, headers: headers)}
      end
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
