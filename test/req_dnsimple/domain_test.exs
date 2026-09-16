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

  @pagination %{
    "current_page" => 1,
    "per_page" => 1,
    "total_entries" => 1,
    "total_pages" => 1
  }

  # The original domain pages from dnsimple-elixir v10.0.0's all_domains test.
  @legacy_domain_pages Enum.map(
                         [
                           ~s({"data":[{"id":1,"account_id":1010,"registrant_id":null,"name":"example-alpha.com","unicode_name":"example-alpha.com","token":"domain-token","state":"hosted","auto_renew":false,"private_whois":false,"expires_on":null,"created_at":"2014-12-06T15:56:55.573Z","updated_at":"2015-12-09T00:20:56.056Z"}],"pagination":{"current_page":1,"per_page":1,"total_entries":2,"total_pages":2}}),
                           ~s({"data":[{"id":2,"account_id":1010,"registrant_id":21,"name":"example-beta.com","unicode_name":"example-beta.com","token":"domain-token","state":"registered","auto_renew":false,"private_whois":false,"expires_on":"2015-12-06","created_at":"2014-12-06T15:46:52.411Z","updated_at":"2015-12-09T00:20:53.572Z"}],"pagination":{"current_page":2,"per_page":1,"total_entries":2,"total_pages":2}})
                         ],
                         &Jason.decode!/1
                       )

  @legacy_domains [
    %ReqDnsimple.Domain{
      id: 1,
      account_id: 1010,
      registrant_id: nil,
      name: "example-alpha.com",
      unicode_name: "example-alpha.com",
      state: "hosted",
      auto_renew: false,
      private_whois: false,
      expires_at: nil,
      expires_on: nil,
      trustee: nil,
      created_at: ~U[2014-12-06 15:56:55.573Z],
      updated_at: ~U[2015-12-09 00:20:56.056Z]
    },
    %ReqDnsimple.Domain{
      id: 2,
      account_id: 1010,
      registrant_id: 21,
      name: "example-beta.com",
      unicode_name: "example-beta.com",
      state: "registered",
      auto_renew: false,
      private_whois: false,
      expires_at: nil,
      expires_on: ~D[2015-12-06],
      trustee: nil,
      created_at: ~U[2014-12-06 15:46:52.411Z],
      updated_at: ~U[2015-12-09 00:20:53.572Z]
    }
  ]

  test "preserves HTTP headers on domain operations, page responses, and errors" do
    headers = [
      {"x-request-id", "domain-response"},
      {"x-ratelimit-limit", "2400"},
      {"x-ratelimit-remaining", "0"},
      {"x-ratelimit-reset", "1700000000"},
      {"etag", "\"domain-v1\""},
      {"retry-after", "5"}
    ]

    for {operation, status, body, pagination} <- [
          {&ReqDnsimple.Domain.create(&1, 1010, name: "example.test"), 201,
           %{"data" => @domain_data}, nil},
          {&ReqDnsimple.Domain.get(&1, 1010, "example.test"), 200, %{"data" => @domain_data},
           nil},
          {&ReqDnsimple.Domain.list_page(&1, 1010), 200,
           %{"data" => [@domain_data], "pagination" => @pagination}, @pagination},
          {&ReqDnsimple.Domain.delete(&1, 1010, "example.test"), 204, nil, nil}
        ] do
      metadata = %ReqDnsimple.Metadata{
        status: status,
        pagination: pagination,
        request_id: "domain-response",
        rate_limit: 2400,
        rate_limit_remaining: 0,
        rate_limit_reset: 1_700_000_000,
        etag: "\"domain-v1\"",
        retry_after: "5"
      }

      assert {:ok, {data, ^metadata}} = operation.(client(status, body, self(), headers))
      if status == 204, do: assert(is_nil(data))
      assert_received {:request, _request}

      error_body = %{"message" => "retry later"}
      error_reason = %{status: 429, response: error_body}
      error_metadata = %{metadata | status: 429, pagination: nil}

      assert {:error,
              %ReqDnsimple.Error{
                reason: ^error_reason,
                metadata: ^error_metadata
              }} = operation.(client(429, error_body, self(), headers))

      assert_received {:request, _request}
      refute_received {:request, _request}
    end
  end

  test "list_all retains ordered page metadata and the latest complete rate budget" do
    [first_page, second_page] = @legacy_domain_pages

    req =
      response_client(fn
        1 ->
          {200, first_page,
           [
             {"x-request-id", "domain-page-1"},
             {"etag", "\"page-1\""},
             {"x-ratelimit-limit", "2400"},
             {"x-ratelimit-remaining", "1"},
             {"x-ratelimit-reset", "1700000000"},
             {"retry-after", "2"}
           ]}

        2 ->
          {200, second_page,
           [
             {"x-request-id", "domain-page-2"},
             {"etag", "\"page-2\""},
             {"x-ratelimit-limit", "4800"},
             {"x-ratelimit-remaining", "0"},
             {"x-ratelimit-reset", "1700000010"},
             {"retry-after", "5"}
           ]}
      end)

    first_metadata = %ReqDnsimple.Metadata{
      status: 200,
      pagination: first_page["pagination"],
      request_id: "domain-page-1",
      etag: "\"page-1\"",
      rate_limit: 2400,
      rate_limit_remaining: 1,
      rate_limit_reset: 1_700_000_000,
      retry_after: "2"
    }

    second_metadata = %ReqDnsimple.Metadata{
      status: 200,
      pagination: second_page["pagination"],
      request_id: "domain-page-2",
      etag: "\"page-2\"",
      rate_limit: 4800,
      rate_limit_remaining: 0,
      rate_limit_reset: 1_700_000_010,
      retry_after: "5"
    }

    metadata = %ReqDnsimple.Metadata{
      rate_limit: 4800,
      rate_limit_remaining: 0,
      rate_limit_reset: 1_700_000_010,
      retry_after: "5",
      pages: [first_metadata, second_metadata]
    }

    assert {:ok, {@legacy_domains, ^metadata}} = ReqDnsimple.Domain.list_all(req, 1010)
    assert_request(:get, "/v2/1010/domains", %{"page" => 1}, nil)
    assert_request(:get, "/v2/1010/domains", %{"page" => 2}, nil)
    refute_received {:request, _request}
  end

  test "list_all failures retain prior pages and the latest available response context" do
    first_page = hd(@legacy_domain_pages)

    first_metadata = %ReqDnsimple.Metadata{
      status: 200,
      pagination: first_page["pagination"],
      request_id: "domain-first",
      etag: "\"first\"",
      rate_limit_remaining: 9
    }

    failures = [
      {429, %{"message" => "rate limited"},
       [
         {"x-request-id", "domain-failure"},
         {"x-ratelimit-remaining", "0"},
         {"retry-after", "30"}
       ]},
      {:error, :timeout}
    ]

    for failure <- failures do
      req =
        response_client(fn
          1 ->
            {200, first_page,
             [
               {"x-request-id", "domain-first"},
               {"etag", "\"first\""},
               {"x-ratelimit-remaining", "9"}
             ]}

          2 ->
            failure
        end)

      assert {:error, %ReqDnsimple.Error{reason: reason, metadata: metadata}} =
               ReqDnsimple.Domain.list_all(req, 1010)

      case failure do
        {429, body, _headers} ->
          failed_metadata = %ReqDnsimple.Metadata{
            status: 429,
            request_id: "domain-failure",
            rate_limit_remaining: 0,
            retry_after: "30"
          }

          assert reason == %{status: 429, response: body}
          assert metadata == %{failed_metadata | pages: [first_metadata, failed_metadata]}

        {:error, :timeout} ->
          assert %Req.TransportError{reason: :timeout} = reason

          assert metadata == %ReqDnsimple.Metadata{
                   rate_limit_remaining: 9,
                   pages: [first_metadata]
                 }
      end

      assert_request(:get, "/v2/1010/domains", %{"page" => 1}, nil)
      assert_request(:get, "/v2/1010/domains", %{"page" => 2}, nil)
      refute_received {:request, _request}
    end
  end

  describe "list_page/3 and list/3" do
    test "listDomains sends filters, pagination, and ordered sorting once" do
      data =
        Map.merge(@domain_data, %{
          "registrant_id" => 11,
          "state" => "registered",
          "expires_at" => "2027-09-01T10:00:00+02:00",
          "expires_on" => "2027-09-01"
        })

      pagination = %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}

      assert {:ok,
              {[
                 %ReqDnsimple.Domain{
                   registrant_id: 11,
                   state: "registered",
                   expires_at: ~U[2027-09-01 08:00:00Z],
                   expires_on: ~D[2027-09-01]
                 }
               ], %ReqDnsimple.Metadata{pagination: ^pagination}}} =
               ReqDnsimple.Domain.list_page(
                 client(200, %{"data" => [data], "pagination" => pagination}),
                 1010,
                 name_like: "example",
                 registrant_id: 11,
                 sort: [id: :asc, name: :desc, expiration: :asc],
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/domains",
        %{
          "name_like" => "example",
          "registrant_id" => 11,
          "sort" => "id:asc,name:desc,expiration:asc",
          "page" => 2,
          "per_page" => 1
        },
        nil
      )

      refute_received {:request, _request}
    end

    test "listDomains alias requests one page and accepts optional response omissions" do
      data = Map.drop(@domain_data, ["trustee", "expires_on"])
      pagination = %{@pagination | "total_entries" => 0, "total_pages" => 0}

      assert {:ok,
              {[%ReqDnsimple.Domain{trustee: nil, expires_on: nil}],
               %ReqDnsimple.Metadata{pagination: ^pagination}}} =
               ReqDnsimple.Domain.list(
                 client(200, %{"data" => [data], "pagination" => pagination}),
                 0,
                 name_like: ""
               )

      assert_request(:get, "/v2/0/domains", %{"name_like" => ""}, nil)
      refute_received {:request, _request}
    end

    test "listDomains rejects invalid paths and options before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      invalid_calls = [
        {"1010", []},
        {nil, []},
        {1010, [:invalid]},
        {1010, [{:name}]},
        {1010, [unknown: true]},
        {1010, [name_like: nil]},
        {1010, [registrant_id: "11"]},
        {1010, [sort: "id:asc"]},
        {1010, [sort: [created_at: :asc]]},
        {1010, [sort: [id: :sideways]]},
        {1010, [page: 0]},
        {1010, [per_page: 0]},
        {1010, [per_page: 101]}
      ]

      for {account_id, opts} <- invalid_calls do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Domain.list_page(request, account_id, opts)
      end

      refute_received {:request, _request}
    end

    test "listDomains preserves HTTP and transport failures" do
      for status <- [401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"account" => ["is unavailable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Domain.list_page(client(status, body), 1010)

        assert_request(:get, "/v2/1010/domains", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Domain.list_page(transport_error_client(:timeout), 1010)
    end

    test "listDomains rejects malformed successful responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => @pagination},
        %{"data" => [Map.delete(@domain_data, "name")], "pagination" => @pagination},
        %{"data" => [Map.put(@domain_data, "trustee", nil)], "pagination" => @pagination},
        %{
          "data" => [Map.put(@domain_data, "expires_at", "invalid")],
          "pagination" => @pagination
        }
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Domain.list_page(client(200, body), 1010)

        assert_request(:get, "/v2/1010/domains", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  test "domain pages retain valid data and headers when pagination is absent or malformed" do
    invalid = Map.delete(@pagination, "total_entries")
    zero = %{@pagination | "per_page" => 0}

    for {fields, pagination, errors} <- [
          {%{}, nil, %{}},
          {%{"pagination" => nil}, nil, %{}},
          {%{"pagination" => invalid}, nil, %{pagination: {:invalid_pagination, invalid}}},
          {%{"pagination" => zero}, zero, %{}}
        ] do
      body = Map.put(fields, "data", [@domain_data])
      req = client(200, body, self(), [{"x-request-id", "domain-page"}])

      assert {:ok,
              {[%ReqDnsimple.Domain{}],
               %ReqDnsimple.Metadata{
                 status: 200,
                 request_id: "domain-page",
                 pagination: ^pagination,
                 parse_errors: ^errors
               }}} = ReqDnsimple.Domain.list_page(req, 1010)

      assert_request(:get, "/v2/1010/domains", %{}, nil)
      refute_received {:request, _request}
    end
  end

  describe "list_all/3" do
    test "enumerates from page one while preserving filters, sorting, and server order" do
      second = Map.merge(@domain_data, %{"id" => 2, "name" => "second.test"})

      pages = %{
        1 =>
          {[@domain_data],
           %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}},
        2 =>
          {[second],
           %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}}
      }

      assert {:ok,
              {[
                 %ReqDnsimple.Domain{id: 1, name: "example.test"},
                 %ReqDnsimple.Domain{id: 2, name: "second.test"}
               ], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Domain.list_all(page_client(pages), 1010,
                 name_like: "test",
                 registrant_id: 11,
                 sort: [expiration: :desc],
                 per_page: 1
               )

      query = %{
        "name_like" => "test",
        "registrant_id" => 11,
        "sort" => "expiration:desc",
        "per_page" => 1
      }

      assert_request(:get, "/v2/1010/domains", Map.put(query, "page", 1))
      assert_request(:get, "/v2/1010/domains", Map.put(query, "page", 2))
      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      assert {:error, %ReqDnsimple.Error{reason: {:invalid_option, :page}, metadata: nil}} =
               ReqDnsimple.Domain.list_all(request, 1010, page: 2)

      for opts <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Domain.list_all(request, 1010, opts)
      end

      refute_received {:request, _request}
    end

    test "aborts on later-page failures and rejects non-progressing pagination" do
      first_page =
        %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      http_client =
        response_client(fn
          1 -> {200, %{"data" => [@domain_data], "pagination" => first_page}}
          2 -> {503, %{"message" => "unavailable"}}
        end)

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 503, response: %{"message" => "unavailable"}},
                metadata: %ReqDnsimple.Metadata{status: 503}
              }} =
               ReqDnsimple.Domain.list_all(http_client, 1010)

      assert_request(:get, "/v2/1010/domains", %{"page" => 1})
      assert_request(:get, "/v2/1010/domains", %{"page" => 2})

      repeated = %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      assert {:error,
              %ReqDnsimple.Error{
                reason: {:invalid_pagination, ^repeated},
                metadata: %ReqDnsimple.Metadata{}
              }} =
               ReqDnsimple.Domain.list_all(
                 response_client(fn _page ->
                   {200, %{"data" => [@domain_data], "pagination" => repeated}}
                 end),
                 1010
               )

      assert_request(:get, "/v2/1010/domains", %{"page" => 1})
      assert_request(:get, "/v2/1010/domains", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "create/3" do
    test "createDomain sends one name and returns the typed hosted domain" do
      assert {:ok,
              {%ReqDnsimple.Domain{
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
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Domain.create(
                 client(201, %{"data" => @domain_data}),
                 1010,
                 name: "example.test"
               )

      assert_request(:post, "/v2/1010/domains", %{}, %{"name" => "example.test"})
      refute_received {:request, _request}
    end

    test "createDomain preserves empty names and accepts older optional response omissions" do
      data = Map.drop(@domain_data, ["trustee", "expires_on"])

      assert {:ok, {%ReqDnsimple.Domain{trustee: nil, expires_on: nil}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Domain.create(client(201, %{"data" => data}), 0, name: "")

      assert_request(:post, "/v2/0/domains", %{}, %{"name" => ""})
      refute_received {:request, _request}
    end

    test "createDomain rejects invalid attributes before HTTP" do
      request = client(201, %{"data" => @domain_data})

      for {account_id, attrs} <- [
            {"1010", [name: "example.test"]},
            {nil, [name: "example.test"]},
            {1010, [:invalid]},
            {1010, [{:name}]},
            {1010, []},
            {1010, [name: nil]},
            {1010, [name: false]},
            {1010, [name: 0]},
            {1010, [name: []]},
            {1010, [name: %{}]},
            {1010, [name: "example.test", unknown: true]}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Domain.create(request, account_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "createDomain preserves documented and shared HTTP failures" do
      for status <- [400, 402, 406, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"name" => ["must be verified"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Domain.create(
                   client(status, body),
                   1010,
                   name: "example.test"
                 )

        assert_request(:post, "/v2/1010/domains", %{}, %{"name" => "example.test"})
        refute_received {:request, _request}
      end
    end

    test "createDomain returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@domain_data, "name")},
        %{"data" => Map.put(@domain_data, "state", "unknown")},
        %{"data" => Map.put(@domain_data, "expires_at", "not-a-timestamp")},
        %{"data" => Map.put(@domain_data, "expires_on", "not-a-date")}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 201, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 201}
                }} =
                 ReqDnsimple.Domain.create(
                   client(201, body),
                   1010,
                   name: "example.test"
                 )

        assert_request(:post, "/v2/1010/domains", %{}, %{"name" => "example.test"})
        refute_received {:request, _request}
      end
    end

    test "createDomain rejects an unexpected success status" do
      body = %{"data" => @domain_data}

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 200, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 200}
              }} =
               ReqDnsimple.Domain.create(
                 client(200, body),
                 1010,
                 name: "example.test"
               )

      assert_request(:post, "/v2/1010/domains", %{}, %{"name" => "example.test"})
      refute_received {:request, _request}
    end

    test "createDomain preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Domain.create(
                 transport_error_client(:timeout),
                 1010,
                 name: "example.test"
               )
    end
  end

  describe "get/3" do
    test "getDomain sends one bodyless request and returns a typed hosted domain" do
      assert {:ok,
              {%ReqDnsimple.Domain{
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
               }, %ReqDnsimple.Metadata{}}} =
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
              {%ReqDnsimple.Domain{
                 registrant_id: 11,
                 state: "registered",
                 auto_renew: true,
                 private_whois: true,
                 expires_at: ~U[2027-09-01 08:00:00Z],
                 expires_on: ~D[2027-09-01]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Domain.get(client(200, %{"data" => data}), 1010, 1)

      assert_request(:get, "/v2/1010/domains/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomain accepts an older payload omitting trustee" do
      data = Map.delete(@domain_data, "trustee")

      assert {:ok, {%ReqDnsimple.Domain{trustee: nil, state: "hosted"}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Domain.get(client(200, %{"data" => data}), 1010, "example.test")

      assert_request(:get, "/v2/1010/domains/example.test")
    end

    test "getDomain accepts older payloads omitting expires_on and trustee" do
      for omitted_fields <- [["expires_on"], ["expires_on", "trustee"]] do
        data = Map.drop(@domain_data, omitted_fields)

        assert {:ok,
                {%ReqDnsimple.Domain{expires_on: nil, state: "hosted"} = domain,
                 %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Domain.get(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "getDomain preserves explicit zero identifiers" do
      data = Map.merge(@domain_data, %{"id" => 0, "account_id" => 0})

      assert {:ok, {%ReqDnsimple.Domain{id: 0, account_id: 0}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Domain.get(client(200, %{"data" => data}), 0, 0)

      assert_request(:get, "/v2/0/domains/0", %{}, nil)
    end

    test "getDomain preserves documented and shared HTTP failures" do
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Domain.get(client(200, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/domains/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomain preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Domain.get(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "delete/3" do
    test "deleteDomain sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Domain.delete(client(204, ""), 1010, "example.test")

      assert_request(:delete, "/v2/1010/domains/example.test", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomain accepts an integer domain ID" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Domain.delete(client(204, nil), 1010, 42)

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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Domain.delete(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "deleteDomain preserves explicit zero identifiers" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Domain.delete(client(204, nil), 0, 0)

      assert_request(:delete, "/v2/0/domains/0", %{}, nil)
    end

    test "deleteDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["cannot be deleted"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Domain.delete(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomain rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Domain.delete(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomain preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Domain.delete(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "legacy responses without expires_at" do
    test "get preserves date-only expiry without inventing a timestamp" do
      for {%{"data" => [data]}, expected} <- Enum.zip(@legacy_domain_pages, @legacy_domains) do
        assert {:ok, {^expected, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Domain.get(client(200, %{"data" => data}), 1010, data["name"])

        assert_request(:get, "/v2/1010/domains/#{data["name"]}", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "create accepts a legacy hosted domain" do
      [%{"data" => [data]} | _] = @legacy_domain_pages
      [expected | _] = @legacy_domains

      assert {:ok, {^expected, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Domain.create(client(201, %{"data" => data}), 1010, name: data["name"])

      assert_request(:post, "/v2/1010/domains", %{}, %{"name" => data["name"]})
      refute_received {:request, _request}
    end

    test "list_page preserves each original page and its pagination" do
      for {body, expected} <- Enum.zip(@legacy_domain_pages, @legacy_domains) do
        pagination = body["pagination"]
        page = pagination["current_page"]

        assert {:ok, {[^expected], %ReqDnsimple.Metadata{pagination: ^pagination}}} =
                 ReqDnsimple.Domain.list_page(client(200, body), 1010, page: page, per_page: 1)

        assert_request(:get, "/v2/1010/domains", %{"page" => page, "per_page" => 1}, nil)
        refute_received {:request, _request}
      end
    end

    test "list_all enumerates both original pages in order" do
      pages =
        Map.new(@legacy_domain_pages, fn %{"data" => data, "pagination" => pagination} ->
          {pagination["current_page"], {data, pagination}}
        end)

      assert {:ok, {@legacy_domains, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Domain.list_all(page_client(pages), 1010, per_page: 1)

      assert_request(:get, "/v2/1010/domains", %{"page" => 1, "per_page" => 1}, nil)
      assert_request(:get, "/v2/1010/domains", %{"page" => 2, "per_page" => 1}, nil)
      refute_received {:request, _request}
    end

    test "rejects malformed explicit expiry fields and required timestamps" do
      [%{"data" => [data]} | _] = @legacy_domain_pages

      for {field, value} <- [
            {"expires_at", "not-a-timestamp"},
            {"expires_at", false},
            {"expires_at", 0},
            {"expires_on", "2015-02-30"},
            {"expires_on", false},
            {"expires_on", 0},
            {"created_at", nil},
            {"created_at", "not-a-timestamp"},
            {"updated_at", nil},
            {"updated_at", "not-a-timestamp"}
          ] do
        body = %{"data" => Map.put(data, field, value)}

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Domain.get(client(200, body), 1010, data["name"])

        assert_request(:get, "/v2/1010/domains/#{data["name"]}", %{}, nil)
        refute_received {:request, _request}
      end
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

      page =
        request.url.query
        |> then(&URI.decode_query(&1 || ""))
        |> Map.get("page", "1")
        |> String.to_integer()

      case response_for_page.(page) do
        {:error, reason} ->
          {request, %Req.TransportError{reason: reason}}

        {status, body, headers} ->
          {request, Req.Response.new(status: status, body: body, headers: headers)}

        {status, body} ->
          {request, %Req.Response{status: status, body: body}}
      end
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
