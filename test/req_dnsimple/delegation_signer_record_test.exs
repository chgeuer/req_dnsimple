defmodule ReqDnsimple.DelegationSignerRecordTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @ds_data %{
    "id" => 1,
    "domain_id" => 100,
    "algorithm" => "13",
    "digest" => "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "digest_type" => "2",
    "keytag" => "12345",
    "public_key" => nil,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  @pagination %{
    "current_page" => 1,
    "per_page" => 1,
    "total_entries" => 1,
    "total_pages" => 1
  }

  test "preserves HTTP headers on DS operations, page responses, and errors" do
    headers = [
      {"x-request-id", "ds-response"},
      {"x-ratelimit-remaining", "0"},
      {"retry-after", "5"}
    ]

    for {operation, status, body, pagination} <- [
          {&ReqDnsimple.DelegationSignerRecord.create(&1, 1010, "example.test",
             algorithm: "13",
             digest: @ds_data["digest"],
             digest_type: "2",
             keytag: "12345"
           ), 201, %{"data" => @ds_data}, nil},
          {&ReqDnsimple.DelegationSignerRecord.get(&1, 1010, "example.test", 1), 200,
           %{"data" => @ds_data}, nil},
          {&ReqDnsimple.DelegationSignerRecord.list_page(&1, 1010, "example.test"), 200,
           %{"data" => [@ds_data], "pagination" => @pagination}, @pagination},
          {&ReqDnsimple.DelegationSignerRecord.delete(&1, 1010, "example.test", 1), 204, nil, nil}
        ] do
      metadata = %ReqDnsimple.Metadata{
        status: status,
        pagination: pagination,
        request_id: "ds-response",
        rate_limit_remaining: 0,
        retry_after: "5"
      }

      assert {:ok, {data, ^metadata}} = operation.(client(status, body, self(), headers))
      if status == 204, do: assert(is_nil(data))
      assert_received {:request, _request}

      error_body = %{"message" => "retry later"}
      error_metadata = %{metadata | status: 429, pagination: nil}

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 429, response: ^error_body},
                metadata: ^error_metadata
              }} = operation.(client(429, error_body, self(), headers))

      assert_received {:request, _request}
      refute_received {:request, _request}
    end
  end

  describe "list_page/4 and list/4" do
    test "listDomainDelegationSignerRecords sends ordered options once and returns typed data" do
      key_data =
        Map.merge(@ds_data, %{
          "id" => 2,
          "digest" => nil,
          "digest_type" => nil,
          "keytag" => nil,
          "public_key" => "ZmFrZS1vZmZsaW5lLXB1YmxpYy1rZXk="
        })

      pagination = %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}

      assert {:ok,
              {[
                 %ReqDnsimple.DelegationSignerRecord{
                   id: 1,
                   algorithm: "13",
                   digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                   public_key: nil
                 },
                 %ReqDnsimple.DelegationSignerRecord{
                   id: 2,
                   digest: nil,
                   digest_type: nil,
                   keytag: nil,
                   public_key: "ZmFrZS1vZmZsaW5lLXB1YmxpYy1rZXk="
                 }
               ], %ReqDnsimple.Metadata{pagination: ^pagination}}} =
               ReqDnsimple.DelegationSignerRecord.list_page(
                 client(200, %{"data" => [@ds_data, key_data], "pagination" => pagination}),
                 1010,
                 "example.test",
                 sort: [id: :asc, created_at: :desc],
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/ds_records",
        %{"sort" => "id:asc,created_at:desc", "page" => 2, "per_page" => 1},
        nil
      )

      refute_received {:request, _request}
    end

    test "listDomainDelegationSignerRecords alias requests one empty page with no defaults" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 0,
        "total_pages" => 0
      }

      assert {:ok, {[], %ReqDnsimple.Metadata{pagination: ^pagination}}} =
               ReqDnsimple.DelegationSignerRecord.list(
                 client(200, %{"data" => [], "pagination" => pagination}),
                 0,
                 42
               )

      assert_request(:get, "/v2/0/domains/42/ds_records", %{}, nil)
      refute_received {:request, _request}
    end

    test "listDomainDelegationSignerRecords rejects invalid paths and options before HTTP" do
      request = client(200, %{"data" => [@ds_data], "pagination" => @pagination})

      invalid_calls = [
        {"1010", "example.test", []},
        {nil, "example.test", []},
        {1010, nil, []},
        {1010, 1.5, []},
        {1010, [], []},
        {1010, "example.test", [:invalid]},
        {1010, "example.test", [{:name}]},
        {1010, "example.test", [unknown: true]},
        {1010, "example.test", [sort: "id:asc"]},
        {1010, "example.test", [sort: [domain_id: :asc]]},
        {1010, "example.test", [sort: [id: :sideways]]},
        {1010, "example.test", [page: 0]},
        {1010, "example.test", [per_page: 0]},
        {1010, "example.test", [per_page: 101]}
      ]

      for {account_id, domain, opts} <- invalid_calls do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.DelegationSignerRecord.list_page(
                   request,
                   account_id,
                   domain,
                   opts
                 )
      end

      refute_received {:request, _request}
    end

    test "listDomainDelegationSignerRecords preserves HTTP and transport failures" do
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
                 ReqDnsimple.DelegationSignerRecord.list_page(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/example.test/ds_records", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.DelegationSignerRecord.list_page(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end

    test "listDomainDelegationSignerRecords rejects malformed successful responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => @pagination},
        %{"data" => %{}, "pagination" => @pagination},
        %{"data" => [Map.delete(@ds_data, "digest")], "pagination" => @pagination},
        %{"data" => [Map.put(@ds_data, "digest", 123)], "pagination" => @pagination},
        %{"data" => [Map.put(@ds_data, "created_at", "invalid")], "pagination" => @pagination}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.DelegationSignerRecord.list_page(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/example.test/ds_records", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  test "DS pages retain valid data and headers when pagination is absent or malformed" do
    invalid = Map.delete(@pagination, "total_entries")
    zero = %{@pagination | "per_page" => 0}

    for {fields, pagination, errors} <- [
          {%{}, nil, %{}},
          {%{"pagination" => nil}, nil, %{}},
          {%{"pagination" => invalid}, nil, %{pagination: {:invalid_pagination, invalid}}},
          {%{"pagination" => zero}, zero, %{}}
        ] do
      body = Map.put(fields, "data", [@ds_data])
      req = client(200, body, self(), [{"x-request-id", "ds-page"}])

      assert {:ok,
              {[%ReqDnsimple.DelegationSignerRecord{}],
               %ReqDnsimple.Metadata{
                 status: 200,
                 request_id: "ds-page",
                 pagination: ^pagination,
                 parse_errors: ^errors
               }}} = ReqDnsimple.DelegationSignerRecord.list_page(req, 1010, "example.test")

      assert_request(:get, "/v2/1010/domains/example.test/ds_records", %{}, nil)
      refute_received {:request, _request}
    end
  end

  describe "list_all/4" do
    test "enumerates from page one while preserving options and server order" do
      second = Map.put(@ds_data, "id", 2)

      pages = %{
        1 =>
          {[@ds_data],
           %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}},
        2 =>
          {[second],
           %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}}
      }

      assert {:ok,
              {[
                 %ReqDnsimple.DelegationSignerRecord{id: 1},
                 %ReqDnsimple.DelegationSignerRecord{id: 2}
               ], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.DelegationSignerRecord.list_all(
                 page_client(pages),
                 1010,
                 "example.test",
                 sort: [created_at: :desc, id: :asc],
                 per_page: 1
               )

      query = %{"sort" => "created_at:desc,id:asc", "per_page" => 1}

      assert_request(
        :get,
        "/v2/1010/domains/example.test/ds_records",
        Map.put(query, "page", 1)
      )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/ds_records",
        Map.put(query, "page", 2)
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      assert {:error, %ReqDnsimple.Error{reason: {:invalid_option, :page}, metadata: nil}} =
               ReqDnsimple.DelegationSignerRecord.list_all(
                 request,
                 1010,
                 "example.test",
                 page: 2
               )

      for opts <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.DelegationSignerRecord.list_all(
                   request,
                   1010,
                   "example.test",
                   opts
                 )
      end

      refute_received {:request, _request}
    end

    test "aborts on later-page failures and rejects non-progressing pagination" do
      first_page =
        %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      http_client =
        response_client(fn
          1 -> {200, %{"data" => [@ds_data], "pagination" => first_page}}
          2 -> {503, %{"message" => "unavailable"}}
        end)

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 503, response: %{"message" => "unavailable"}},
                metadata: %ReqDnsimple.Metadata{status: 503}
              }} =
               ReqDnsimple.DelegationSignerRecord.list_all(
                 http_client,
                 1010,
                 "example.test"
               )

      assert_request(:get, "/v2/1010/domains/example.test/ds_records", %{"page" => 1})
      assert_request(:get, "/v2/1010/domains/example.test/ds_records", %{"page" => 2})

      repeated = %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      assert {:error,
              %ReqDnsimple.Error{
                reason: {:invalid_pagination, ^repeated},
                metadata: %ReqDnsimple.Metadata{}
              }} =
               ReqDnsimple.DelegationSignerRecord.list_all(
                 response_client(fn _page ->
                   {200, %{"data" => [@ds_data], "pagination" => repeated}}
                 end),
                 1010,
                 "example.test"
               )

      assert_request(:get, "/v2/1010/domains/example.test/ds_records", %{"page" => 1})
      assert_request(:get, "/v2/1010/domains/example.test/ds_records", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "create/4" do
    test "createDomainDelegationSignerRecord sends complete DS data and returns a typed record" do
      attrs = [
        algorithm: "13",
        digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        digest_type: "2",
        keytag: "12345"
      ]

      assert {:ok,
              {%ReqDnsimple.DelegationSignerRecord{
                 id: 1,
                 domain_id: 100,
                 algorithm: "13",
                 digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                 digest_type: "2",
                 keytag: "12345",
                 public_key: nil,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.DelegationSignerRecord.create(
                 client(201, %{"data" => @ds_data}),
                 1010,
                 "example.test",
                 attrs
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/ds_records",
        %{},
        Map.new(attrs)
      )

      refute_received {:request, _request}
    end

    test "createDomainDelegationSignerRecord sends KEY data without omitted DS fields" do
      public_key = "ZmFrZS1vZmZsaW5lLXB1YmxpYy1rZXk="

      data =
        Map.merge(@ds_data, %{
          "digest" => nil,
          "digest_type" => nil,
          "keytag" => nil,
          "public_key" => public_key
        })

      assert {:ok,
              {%ReqDnsimple.DelegationSignerRecord{
                 algorithm: "",
                 digest: nil,
                 digest_type: nil,
                 keytag: nil,
                 public_key: ^public_key
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.DelegationSignerRecord.create(
                 client(201, %{"data" => Map.put(data, "algorithm", "")}),
                 1010,
                 42,
                 algorithm: "",
                 public_key: public_key
               )

      assert_request(
        :post,
        "/v2/1010/domains/42/ds_records",
        %{},
        %{"algorithm" => "", "public_key" => public_key}
      )

      refute_received {:request, _request}
    end

    test "createDomainDelegationSignerRecord rejects invalid paths and attributes before HTTP" do
      request = client(201, %{"data" => @ds_data})

      invalid_inputs = [
        {"1010", "example.test", [algorithm: "13", public_key: "key"]},
        {nil, "example.test", [algorithm: "13", public_key: "key"]},
        {1010, nil, [algorithm: "13", public_key: "key"]},
        {1010, 1.5, [algorithm: "13", public_key: "key"]},
        {1010, [], [algorithm: "13", public_key: "key"]},
        {1010, "example.test", [:invalid]},
        {1010, "example.test", [{:algorithm}]},
        {1010, "example.test", []},
        {1010, "example.test", [algorithm: nil, public_key: "key"]},
        {1010, "example.test", [algorithm: false, public_key: "key"]},
        {1010, "example.test", [algorithm: 0, public_key: "key"]},
        {1010, "example.test", [algorithm: [], public_key: "key"]},
        {1010, "example.test", [algorithm: %{}, public_key: "key"]},
        {1010, "example.test", [algorithm: "13"]},
        {1010, "example.test", [algorithm: "13", digest: "digest"]},
        {1010, "example.test", [algorithm: "13", digest_type: "2"]},
        {1010, "example.test", [algorithm: "13", keytag: "12345"]},
        {1010, "example.test", [algorithm: "13", public_key: nil]},
        {1010, "example.test", [algorithm: "13", public_key: false]},
        {1010, "example.test", [algorithm: "13", public_key: 0]},
        {1010, "example.test", [algorithm: "13", public_key: []]},
        {1010, "example.test", [algorithm: "13", public_key: %{}]},
        {1010, "example.test", [algorithm: "13", public_key: "key", unknown: true]}
      ]

      for {account_id, domain, attrs} <- invalid_inputs do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.DelegationSignerRecord.create(
                   request,
                   account_id,
                   domain,
                   attrs
                 )
      end

      refute_received {:request, _request}
    end

    test "createDomainDelegationSignerRecord preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"digest" => ["is invalid"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.DelegationSignerRecord.create(
                   client(status, body),
                   1010,
                   "example.test",
                   algorithm: "13",
                   public_key: "key"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/ds_records",
          %{},
          %{"algorithm" => "13", "public_key" => "key"}
        )

        refute_received {:request, _request}
      end
    end

    test "createDomainDelegationSignerRecord returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@ds_data, "id")},
        %{"data" => Map.put(@ds_data, "algorithm", 13)},
        %{"data" => Map.put(@ds_data, "public_key", 123)},
        %{"data" => Map.put(@ds_data, "created_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 201, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 201}
                }} =
                 ReqDnsimple.DelegationSignerRecord.create(
                   client(201, body),
                   1010,
                   "example.test",
                   algorithm: "13",
                   public_key: "key"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/ds_records",
          %{},
          %{"algorithm" => "13", "public_key" => "key"}
        )

        refute_received {:request, _request}
      end

      body = %{"data" => @ds_data}

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 200, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 200}
              }} =
               ReqDnsimple.DelegationSignerRecord.create(
                 client(200, body),
                 1010,
                 "example.test",
                 algorithm: "13",
                 public_key: "key"
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/ds_records",
        %{},
        %{"algorithm" => "13", "public_key" => "key"}
      )

      refute_received {:request, _request}
    end

    test "createDomainDelegationSignerRecord preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.DelegationSignerRecord.create(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 algorithm: "13",
                 public_key: "key"
               )
    end
  end

  describe "get/4" do
    test "getDomainDelegationSignerRecord sends one bodyless request and returns typed DS data" do
      assert {:ok,
              {%ReqDnsimple.DelegationSignerRecord{
                 id: 1,
                 domain_id: 100,
                 algorithm: "13",
                 digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                 digest_type: "2",
                 keytag: "12345",
                 public_key: nil,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.DelegationSignerRecord.get(
                 client(200, %{"data" => @ds_data}),
                 1010,
                 "example.test",
                 1
               )

      assert_request(:get, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomainDelegationSignerRecord decodes KEY data with unused DS fields null" do
      data =
        Map.merge(@ds_data, %{
          "digest" => nil,
          "digest_type" => nil,
          "keytag" => nil,
          "public_key" => "ZmFrZS1vZmZsaW5lLXB1YmxpYy1rZXk="
        })

      assert {:ok,
              {%ReqDnsimple.DelegationSignerRecord{
                 algorithm: "13",
                 digest: nil,
                 digest_type: nil,
                 keytag: nil,
                 public_key: "ZmFrZS1vZmZsaW5lLXB1YmxpYy1rZXk="
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.DelegationSignerRecord.get(client(200, %{"data" => data}), 1010, 42, 1)

      assert_request(:get, "/v2/1010/domains/42/ds_records/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomainDelegationSignerRecord rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @ds_data})

      for {account_id, domain, ds_record_id} <- [
            {"1010", "example.test", 1},
            {nil, "example.test", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "example.test", "1"},
            {1010, "example.test", nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.DelegationSignerRecord.get(
                   request,
                   account_id,
                   domain,
                   ds_record_id
                 )
      end

      refute_received {:request, _request}
    end

    test "getDomainDelegationSignerRecord preserves explicit zero identifiers" do
      data = Map.merge(@ds_data, %{"id" => 0, "domain_id" => 0})

      assert {:ok,
              {%ReqDnsimple.DelegationSignerRecord{id: 0, domain_id: 0}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.DelegationSignerRecord.get(
                 client(200, %{"data" => data}),
                 0,
                 0,
                 0
               )

      assert_request(:get, "/v2/0/domains/0/ds_records/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "getDomainDelegationSignerRecord preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"ds_record" => ["is unavailable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.DelegationSignerRecord.get(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:get, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomainDelegationSignerRecord returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@ds_data, "id")},
        %{"data" => Map.put(@ds_data, "algorithm", 13)},
        %{"data" => Map.put(@ds_data, "digest", 123)},
        %{"data" => Map.put(@ds_data, "created_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.DelegationSignerRecord.get(
                   client(200, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:get, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [{201, %{"data" => @ds_data}}, {204, nil}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.DelegationSignerRecord.get(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:get, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getDomainDelegationSignerRecord preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.DelegationSignerRecord.get(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 1
               )
    end
  end

  describe "delete/4" do
    test "deleteDomainDelegationSignerRecord sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.DelegationSignerRecord.delete(
                 client(204, ""),
                 1010,
                 "example.test",
                 1
               )

      assert_request(:delete, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomainDelegationSignerRecord accepts an integer domain ID" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.DelegationSignerRecord.delete(client(204, nil), 1010, 42, 1)

      assert_request(:delete, "/v2/1010/domains/42/ds_records/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomainDelegationSignerRecord rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain, ds_record_id} <- [
            {"1010", "example.test", 1},
            {nil, "example.test", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "example.test", "1"},
            {1010, "example.test", nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.DelegationSignerRecord.delete(
                   request,
                   account_id,
                   domain,
                   ds_record_id
                 )
      end

      refute_received {:request, _request}
    end

    test "deleteDomainDelegationSignerRecord preserves explicit zero identifiers" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.DelegationSignerRecord.delete(client(204, nil), 0, 0, 0)

      assert_request(:delete, "/v2/0/domains/0/ds_records/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomainDelegationSignerRecord preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"ds_record" => ["cannot be deleted"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.DelegationSignerRecord.delete(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:delete, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomainDelegationSignerRecord rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.DelegationSignerRecord.delete(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:delete, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomainDelegationSignerRecord preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.DelegationSignerRecord.delete(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
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

      page =
        request.url.query
        |> then(&URI.decode_query(&1 || ""))
        |> Map.get("page", "1")
        |> String.to_integer()

      case response_for_page.(page) do
        {:error, reason} ->
          {request, %Req.TransportError{reason: reason}}

        {status, body} ->
          {request, %Req.Response{status: status, body: body}}
      end
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
