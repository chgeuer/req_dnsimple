defmodule ReqDnsimple.TemplateRecordTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  test "template-record data, bodyless successes, and HTTP errors retain response headers" do
    headers = [
      {"x-ratelimit-remaining", "0"},
      {"x-request-id", "record-response"},
      {"retry-after", "120"}
    ]

    assert {:ok,
            {%ReqDnsimple.TemplateRecord{id: 1},
             %ReqDnsimple.Metadata{
               status: 200,
               rate_limit_remaining: 0,
               request_id: "record-response"
             }}} =
             ReqDnsimple.TemplateRecord.get(
               client(200, template_record_body(nil), self(), headers),
               1010,
               "offline-template",
               1
             )

    assert_request(:get, "/v2/1010/templates/offline-template/records/1")

    assert {:ok,
            {nil,
             %ReqDnsimple.Metadata{
               status: 204,
               rate_limit_remaining: 0,
               request_id: "record-response"
             }}} =
             ReqDnsimple.TemplateRecord.delete(
               client(204, nil, self(), headers),
               1010,
               "offline-template",
               1
             )

    assert_request(:delete, "/v2/1010/templates/offline-template/records/1")

    assert {:error,
            %ReqDnsimple.Error{
              reason: reason,
              metadata: %ReqDnsimple.Metadata{
                status: 429,
                rate_limit_remaining: 0,
                request_id: "record-response",
                retry_after: "120"
              }
            }} =
             ReqDnsimple.TemplateRecord.get(
               client(429, %{"message" => "rate limited"}, self(), headers),
               1010,
               "offline-template",
               1
             )

    assert reason.status == 429
    refute Map.has_key?(reason, :retry_after)
    assert_request(:get, "/v2/1010/templates/offline-template/records/1")
    refute_received {:request, _request}
  end

  describe "list_page/4 and list/4" do
    test "listTemplateRecords sends ordered options once and returns typed data" do
      pagination = %{
        "current_page" => 2,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      records = [
        template_record_body(0)["data"],
        template_record_body("10")["data"] |> Map.put("id", 2)
      ]

      assert {:ok,
              {[
                 %ReqDnsimple.TemplateRecord{
                   id: 1,
                   name: "",
                   content: "mail.{{domain}}",
                   ttl: 0,
                   priority: 0
                 },
                 %ReqDnsimple.TemplateRecord{id: 2, priority: 10}
               ], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.TemplateRecord.list_page(
                 client(200, %{"data" => records, "pagination" => pagination}),
                 1010,
                 "offline-template",
                 sort: [id: :asc, name: :desc, content: :asc, type: :desc],
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/templates/offline-template/records",
        %{
          "sort" => "id:asc,name:desc,content:asc,type:desc",
          "page" => 2,
          "per_page" => 1
        },
        nil
      )

      refute_received {:request, _request}
    end

    test "listTemplateRecords alias requests one empty page without adding defaults" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 0,
        "total_pages" => 0
      }

      assert {:ok, {[], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.TemplateRecord.list(
                 client(200, %{"data" => [], "pagination" => pagination}),
                 0,
                 42
               )

      assert_request(:get, "/v2/0/templates/42/records", %{}, nil)
      refute_received {:request, _request}
    end

    test "listTemplateRecords accepts nullable priority and empty template identifiers" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      assert {:ok,
              {[%ReqDnsimple.TemplateRecord{priority: nil}],
               %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.TemplateRecord.list_page(
                 client(200, %{
                   "data" => [template_record_body(nil)["data"]],
                   "pagination" => pagination
                 }),
                 1010,
                 ""
               )

      assert_request(:get, "/v2/1010/templates//records", %{}, nil)
      refute_received {:request, _request}
    end

    test "listTemplateRecords rejects invalid paths and options before HTTP" do
      request =
        client(200, %{
          "data" => [],
          "pagination" => %{
            "current_page" => 1,
            "per_page" => 30,
            "total_entries" => 0,
            "total_pages" => 0
          }
        })

      invalid_calls = [
        {"1010", "offline-template", []},
        {nil, "offline-template", []},
        {1010, nil, []},
        {1010, 1.5, []},
        {1010, [], []},
        {1010, "offline-template", [:invalid]},
        {1010, "offline-template", [{:name}]},
        {1010, "offline-template", [unknown: true]},
        {1010, "offline-template", [sort: "id:asc"]},
        {1010, "offline-template", [sort: [created_at: :asc]]},
        {1010, "offline-template", [sort: [id: :sideways]]},
        {1010, "offline-template", [page: 0]},
        {1010, "offline-template", [per_page: 0]},
        {1010, "offline-template", [per_page: 101]}
      ]

      for {account_id, template, opts} <- invalid_calls do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.TemplateRecord.list_page(request, account_id, template, opts)
      end

      refute_received {:request, _request}
    end

    test "listTemplateRecords preserves HTTP and transport failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["is unavailable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.TemplateRecord.list_page(
                   client(status, body),
                   1010,
                   "offline-template"
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.TemplateRecord.list_page(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template"
               )
    end

    test "listTemplateRecords rejects malformed successful responses" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      record = template_record_body(nil)["data"]

      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => pagination},
        %{"data" => %{}, "pagination" => pagination},
        %{"data" => [Map.delete(record, "priority")], "pagination" => pagination},
        %{"data" => [Map.put(record, "priority", "+10")], "pagination" => pagination},
        %{"data" => [Map.put(record, "priority", "10\n")], "pagination" => pagination},
        %{"data" => [Map.put(record, "created_at", "invalid")], "pagination" => pagination}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.TemplateRecord.list_page(
                   client(200, body),
                   1010,
                   "offline-template"
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  test "listTemplateRecords preserves business data when pagination metadata is absent or malformed" do
    pagination = %{
      "current_page" => 1,
      "per_page" => 30,
      "total_entries" => 1,
      "total_pages" => 1
    }

    record = template_record_body(nil)["data"]
    incomplete = Map.delete(pagination, "total_entries")
    zero_page_size = %{pagination | "per_page" => 0}

    for {body, expected_pagination, expected_errors} <- [
          {%{"data" => [record]}, nil, %{}},
          {%{"data" => [record], "pagination" => nil}, nil, %{}},
          {%{"data" => [record], "pagination" => incomplete}, nil,
           %{pagination: {:invalid_pagination, incomplete}}},
          {%{"data" => [record], "pagination" => zero_page_size}, zero_page_size, %{}}
        ] do
      assert {:ok,
              {[%ReqDnsimple.TemplateRecord{id: 1, priority: nil}],
               %ReqDnsimple.Metadata{
                 status: 200,
                 pagination: ^expected_pagination,
                 parse_errors: ^expected_errors
               }}} =
               ReqDnsimple.TemplateRecord.list_page(client(200, body), 1010, "offline-template")

      assert_request(:get, "/v2/1010/templates/offline-template/records", %{}, nil)
      refute_received {:request, _request}
    end
  end

  describe "list_all/4" do
    test "enumerates from page one while preserving options and server order" do
      first = template_record_body(0)["data"]
      second = template_record_body(nil)["data"] |> Map.put("id", 2)

      pages = %{
        1 =>
          {200,
           %{
             "data" => [first],
             "pagination" => %{
               "current_page" => 1,
               "per_page" => 1,
               "total_entries" => 2,
               "total_pages" => 2
             }
           }},
        2 =>
          {200,
           %{
             "data" => [second],
             "pagination" => %{
               "current_page" => 2,
               "per_page" => 1,
               "total_entries" => 2,
               "total_pages" => 2
             }
           }}
      }

      first_pagination = elem(pages[1], 1)["pagination"]
      second_pagination = elem(pages[2], 1)["pagination"]

      headers =
        Map.new(1..2, fn page ->
          {page,
           [
             {"x-ratelimit-limit", Integer.to_string(4000 + page)},
             {"x-ratelimit-remaining", Integer.to_string(4000 - page)},
             {"x-ratelimit-reset", Integer.to_string(1_800_000_000 + page)},
             {"x-request-id", "page-#{page}"},
             {"etag", ~s("page-#{page}")},
             {"retry-after", Integer.to_string(30 - page)}
           ]}
        end)

      assert {:ok,
              {[
                 %ReqDnsimple.TemplateRecord{id: 1, priority: 0},
                 %ReqDnsimple.TemplateRecord{id: 2, priority: nil}
               ],
               %ReqDnsimple.Metadata{
                 status: nil,
                 pagination: nil,
                 rate_limit: 4002,
                 rate_limit_remaining: 3998,
                 rate_limit_reset: 1_800_000_002,
                 request_id: nil,
                 etag: nil,
                 retry_after: "28",
                 pages: [
                   %ReqDnsimple.Metadata{
                     status: 200,
                     pagination: ^first_pagination,
                     rate_limit: 4001,
                     rate_limit_remaining: 3999,
                     rate_limit_reset: 1_800_000_001,
                     request_id: "page-1",
                     etag: ~s("page-1"),
                     retry_after: "29",
                     pages: []
                   },
                   %ReqDnsimple.Metadata{
                     status: 200,
                     pagination: ^second_pagination,
                     rate_limit: 4002,
                     rate_limit_remaining: 3998,
                     rate_limit_reset: 1_800_000_002,
                     request_id: "page-2",
                     etag: ~s("page-2"),
                     retry_after: "28",
                     pages: []
                   }
                 ]
               } = metadata}} =
               ReqDnsimple.TemplateRecord.list_all(
                 page_client(pages, headers),
                 1010,
                 "offline-template",
                 sort: [type: :desc, name: :asc],
                 per_page: 1
               )

      query = %{"sort" => "type:desc,name:asc", "per_page" => 1}

      assert metadata.parse_errors == %{}
      assert Enum.all?(metadata.pages, &(&1.parse_errors == %{}))

      assert_request(
        :get,
        "/v2/1010/templates/offline-template/records",
        Map.put(query, "page", 1)
      )

      assert_request(
        :get,
        "/v2/1010/templates/offline-template/records",
        Map.put(query, "page", 2)
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request =
        client(200, %{
          "data" => [],
          "pagination" => %{
            "current_page" => 1,
            "per_page" => 30,
            "total_entries" => 0,
            "total_pages" => 0
          }
        })

      assert {:error, %ReqDnsimple.Error{reason: {:invalid_option, :page}, metadata: nil}} =
               ReqDnsimple.TemplateRecord.list_all(
                 request,
                 1010,
                 "offline-template",
                 page: 2
               )

      for opts <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.TemplateRecord.list_all(
                   request,
                   1010,
                   "offline-template",
                   opts
                 )
      end

      refute_received {:request, _request}
    end

    test "aborts on later-page failures and rejects non-progressing pagination" do
      first_page = %{
        "current_page" => 1,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      http_client =
        page_client(%{
          1 => {200, %{"data" => [template_record_body(0)["data"]], "pagination" => first_page}},
          2 => {503, %{"message" => "unavailable"}}
        })

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 503, response: %{"message" => "unavailable"}},
                metadata: %ReqDnsimple.Metadata{
                  status: 503,
                  pages: [
                    %ReqDnsimple.Metadata{status: 200, pagination: ^first_page, pages: []},
                    %ReqDnsimple.Metadata{status: 503, pagination: nil, pages: []}
                  ]
                }
              }} =
               ReqDnsimple.TemplateRecord.list_all(
                 http_client,
                 1010,
                 "offline-template"
               )

      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 1})
      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 2})

      assert {:error,
              %ReqDnsimple.Error{
                reason: %Req.TransportError{reason: :timeout},
                metadata: %ReqDnsimple.Metadata{
                  status: nil,
                  pagination: nil,
                  request_id: nil,
                  etag: nil,
                  pages: [%ReqDnsimple.Metadata{status: 200, pagination: ^first_page, pages: []}]
                }
              }} =
               ReqDnsimple.TemplateRecord.list_all(
                 page_client(%{
                   1 =>
                     {200,
                      %{"data" => [template_record_body(0)["data"]], "pagination" => first_page}},
                   2 => {:error, :timeout}
                 }),
                 1010,
                 "offline-template"
               )

      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 1})
      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 2})

      assert {:error,
              %ReqDnsimple.Error{
                reason: {:invalid_pagination, ^first_page},
                metadata: %ReqDnsimple.Metadata{
                  status: 200,
                  pagination: ^first_page,
                  pages: [
                    %ReqDnsimple.Metadata{status: 200, pagination: ^first_page, pages: []},
                    %ReqDnsimple.Metadata{status: 200, pagination: ^first_page, pages: []}
                  ]
                }
              }} =
               ReqDnsimple.TemplateRecord.list_all(
                 page_client(%{
                   1 =>
                     {200,
                      %{
                        "data" => [template_record_body(0)["data"]],
                        "pagination" => first_page
                      }},
                   2 =>
                     {200,
                      %{
                        "data" => [template_record_body(0)["data"]],
                        "pagination" => first_page
                      }}
                 }),
                 1010,
                 "offline-template"
               )

      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 1})
      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "create/4" do
    test "createTemplateRecord sends all attributes once and returns the typed record" do
      assert {:ok,
              {%ReqDnsimple.TemplateRecord{
                 id: 1,
                 template_id: 1,
                 name: "",
                 content: "mail.{{domain}}",
                 ttl: 0,
                 priority: 0,
                 type: "MX",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:00:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.TemplateRecord.create(
                 client(201, template_record_body(0)),
                 1010,
                 "offline-template",
                 name: "",
                 type: "MX",
                 content: "mail.{{domain}}",
                 ttl: 0,
                 priority: 0
               )

      assert_request(:post, "/v2/1010/templates/offline-template/records", %{}, %{
        "name" => "",
        "type" => "MX",
        "content" => "mail.{{domain}}",
        "ttl" => 0,
        "priority" => 0
      })

      refute_received {:request, _request}
    end

    test "createTemplateRecord accepts the official SDK lowercase MX example without rewriting it" do
      attrs = [name: "", type: "mx", content: "mx.example.com", ttl: 600, priority: 10]

      body = %{
        "data" => %{
          "id" => 300,
          "template_id" => 268,
          "name" => "",
          "type" => "MX",
          "content" => "mx.example.com",
          "ttl" => 600,
          "priority" => 10,
          "created_at" => "2016-05-03T07:51:33Z",
          "updated_at" => "2016-05-03T07:51:33Z"
        }
      }

      assert {:ok,
              {%ReqDnsimple.TemplateRecord{
                 id: 300,
                 template_id: 268,
                 type: "MX",
                 content: "mx.example.com",
                 ttl: 600,
                 priority: 10
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.TemplateRecord.create(client(201, body), 1010, 268, attrs)

      assert_request(:post, "/v2/1010/templates/268/records", %{}, Map.new(attrs))
      refute_received {:request, _request}
    end

    test "createTemplateRecord preserves uppercase, lowercase, and mixed-case known types" do
      for type <-
            ~w[A AAAA ALIAS CAA CNAME DNSKEY DS HINFO MX NAPTR NS POOL PTR SOA SPF SRV SSHFP TXT URL],
          spelling <- Enum.uniq([type, String.downcase(type), String.capitalize(type)]) do
        body = put_in(template_record_body(nil), ["data", "type"], type)
        attrs = [name: "", type: spelling, content: "{{domain}}"]

        assert {:ok, {%ReqDnsimple.TemplateRecord{type: ^type}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.TemplateRecord.create(client(201, body), 1010, 268, attrs)

        assert_request(:post, "/v2/1010/templates/268/records", %{}, Map.new(attrs))
        refute_received {:request, _request}
      end
    end

    test "createTemplateRecord rejects unknown and nonstring types without HTTP" do
      request = client(201, template_record_body(nil))

      for type <- [nil, false, 0, :mx, [], %{}, "", "INVALID", "invalid", "Mx ", "HTTPS", "ſrv"] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %NimbleOptions.ValidationError{key: :type, value: ^type},
                  metadata: nil
                }} =
                 ReqDnsimple.TemplateRecord.create(request, 1010, 268,
                   name: "",
                   type: type,
                   content: "mx.example.com"
                 )
      end

      refute_received {:request, _request}
    end

    test "createTemplateRecord preserves omitted optional attributes and path identifiers" do
      for {account_id, template} <- [{1010, 42}, {0, 0}, {1010, ""}] do
        assert {:ok, {%ReqDnsimple.TemplateRecord{priority: nil}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.TemplateRecord.create(
                   client(201, template_record_body(nil)),
                   account_id,
                   template,
                   name: "",
                   type: "TXT",
                   content: "{{domain}}"
                 )

        assert_request(
          :post,
          "/v2/#{account_id}/templates/#{template}/records",
          %{},
          %{"name" => "", "type" => "TXT", "content" => "{{domain}}"}
        )

        refute_received {:request, _request}
      end
    end

    test "createTemplateRecord rejects invalid attributes before HTTP" do
      request = client(201, template_record_body(nil))
      valid = [name: "", type: "MX", content: "mail.{{domain}}"]

      invalid_calls = [
        {"1010", "offline-template", valid},
        {nil, "offline-template", valid},
        {1010, nil, valid},
        {1010, 1.5, valid},
        {1010, [], valid},
        {1010, "offline-template", [:invalid]},
        {1010, "offline-template", [{:name}]},
        {1010, "offline-template", []},
        {1010, "offline-template", Keyword.delete(valid, :name)},
        {1010, "offline-template", Keyword.delete(valid, :type)},
        {1010, "offline-template", Keyword.delete(valid, :content)},
        {1010, "offline-template", Keyword.put(valid, :name, nil)},
        {1010, "offline-template", Keyword.put(valid, :name, false)},
        {1010, "offline-template", Keyword.put(valid, :name, 0)},
        {1010, "offline-template", Keyword.put(valid, :name, [])},
        {1010, "offline-template", Keyword.put(valid, :name, %{})},
        {1010, "offline-template", Keyword.put(valid, :type, nil)},
        {1010, "offline-template", Keyword.put(valid, :type, "INVALID")},
        {1010, "offline-template", Keyword.put(valid, :content, nil)},
        {1010, "offline-template", Keyword.put(valid, :content, false)},
        {1010, "offline-template", Keyword.put(valid, :content, 0)},
        {1010, "offline-template", Keyword.put(valid, :content, [])},
        {1010, "offline-template", Keyword.put(valid, :content, %{})},
        {1010, "offline-template", Keyword.put(valid, :ttl, nil)},
        {1010, "offline-template", Keyword.put(valid, :ttl, -1)},
        {1010, "offline-template", Keyword.put(valid, :ttl, false)},
        {1010, "offline-template", Keyword.put(valid, :priority, nil)},
        {1010, "offline-template", Keyword.put(valid, :priority, false)},
        {1010, "offline-template", Keyword.put(valid, :regions, ["global"])},
        {1010, "offline-template", Keyword.put(valid, :integrated_zones, true)},
        {1010, "offline-template", Keyword.put(valid, :unknown, true)}
      ]

      for {account_id, template, attrs} <- invalid_calls do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.TemplateRecord.create(request, account_id, template, attrs)
      end

      refute_received {:request, _request}
    end

    test "createTemplateRecord normalizes nullable and legacy numeric-string priorities" do
      for {wire_priority, priority} <- [{"10", 10}, {"0010", 10}, {-1, -1}, {nil, nil}] do
        assert {:ok, {%ReqDnsimple.TemplateRecord{priority: ^priority}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.TemplateRecord.create(
                   client(201, template_record_body(wire_priority)),
                   1010,
                   "offline-template",
                   name: "",
                   type: "MX",
                   content: "mail.{{domain}}"
                 )

        assert_request(:post, "/v2/1010/templates/offline-template/records", %{}, %{
          "name" => "",
          "type" => "MX",
          "content" => "mail.{{domain}}"
        })

        refute_received {:request, _request}
      end
    end

    test "createTemplateRecord rejects malformed successful responses and unexpected statuses" do
      malformed_responses = [
        {201, %{}},
        {201, %{"data" => nil}},
        {201, %{"data" => %{}}},
        {201, put_in(template_record_body(nil), ["data", "created_at"], "not-a-timestamp")},
        {201, put_in(template_record_body(nil), ["data", "ttl"], -1)},
        {201, put_in(template_record_body(nil), ["data", "priority"], "high")},
        {201, put_in(template_record_body(nil), ["data", "priority"], "+10")},
        {201, put_in(template_record_body(nil), ["data", "priority"], "10\n")},
        {201, put_in(template_record_body(nil), ["data", "type"], "INVALID")},
        {200, template_record_body(nil)}
      ]

      for {status, body} <- malformed_responses do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.TemplateRecord.create(
                   client(status, body),
                   1010,
                   "offline-template",
                   name: "",
                   type: "MX",
                   content: "mail.{{domain}}"
                 )

        assert_request(:post, "/v2/1010/templates/offline-template/records", %{}, %{
          "name" => "",
          "type" => "MX",
          "content" => "mail.{{domain}}"
        })

        refute_received {:request, _request}
      end
    end

    test "createTemplateRecord preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["is invalid"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.TemplateRecord.create(
                   client(status, body),
                   1010,
                   "offline-template",
                   name: "",
                   type: "MX",
                   content: "mail.{{domain}}"
                 )

        assert_request(:post, "/v2/1010/templates/offline-template/records", %{}, %{
          "name" => "",
          "type" => "MX",
          "content" => "mail.{{domain}}"
        })

        refute_received {:request, _request}
      end
    end

    test "createTemplateRecord preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.TemplateRecord.create(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template",
                 name: "",
                 type: "MX",
                 content: "mail.{{domain}}"
               )
    end
  end

  describe "get/4" do
    test "getTemplateRecord retrieves one typed record with one bodyless request" do
      body = template_record_body(0)

      assert {:ok,
              {%ReqDnsimple.TemplateRecord{
                 id: 1,
                 template_id: 1,
                 name: "",
                 content: "mail.{{domain}}",
                 ttl: 0,
                 priority: 0,
                 type: "MX",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:00:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.TemplateRecord.get(
                 client(200, body),
                 1010,
                 "offline-template",
                 1
               )

      assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTemplateRecord normalizes legacy numeric-string and nullable priorities" do
      for {wire_priority, priority} <- [{"10", 10}, {"0010", 10}, {-1, -1}, {nil, nil}] do
        assert {:ok, {%ReqDnsimple.TemplateRecord{priority: ^priority}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(200, template_record_body(wire_priority)),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord accepts integer, zero, and empty template identifiers" do
      for {account_id, template, record_id} <- [
            {1010, 42, 1},
            {0, 0, 0},
            {1010, "", 1}
          ] do
        assert {:ok, {%ReqDnsimple.TemplateRecord{}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(200, template_record_body(nil)),
                   account_id,
                   template,
                   record_id
                 )

        assert_request(
          :get,
          "/v2/#{account_id}/templates/#{template}/records/#{record_id}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord rejects invalid path parameters before HTTP" do
      request = client(200, template_record_body(nil))

      for {account_id, template, record_id} <- [
            {"1010", "offline-template", 1},
            {nil, "offline-template", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "offline-template", "1"},
            {1010, "offline-template", nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.TemplateRecord.get(
                   request,
                   account_id,
                   template,
                   record_id
                 )
      end

      refute_received {:request, _request}
    end

    test "getTemplateRecord rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(template_record_body(nil), ["data", "created_at"], "not-a-timestamp"),
        put_in(template_record_body(nil), ["data", "ttl"], -1),
        put_in(template_record_body(nil), ["data", "priority"], "high"),
        put_in(template_record_body(nil), ["data", "priority"], "+10"),
        put_in(template_record_body(nil), ["data", "priority"], "10\n"),
        put_in(template_record_body(nil), ["data", "type"], "INVALID")
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.TemplateRecord.get(
                   client(200, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["was not found"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.TemplateRecord.get(
                   client(status, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.TemplateRecord.get(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template",
                 1
               )
    end
  end

  describe "delete/4" do
    test "deleteTemplateRecord sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.TemplateRecord.delete(
                 client(204, nil),
                 1010,
                 "offline-template",
                 1
               )

      assert_request(
        :delete,
        "/v2/1010/templates/offline-template/records/1",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "deleteTemplateRecord accepts integer, zero, and empty template identifiers" do
      for {account_id, template, record_id} <- [
            {1010, 42, 1},
            {0, 0, 0},
            {1010, "", 1}
          ] do
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
                 ReqDnsimple.TemplateRecord.delete(
                   client(204, nil),
                   account_id,
                   template,
                   record_id
                 )

        assert_request(
          :delete,
          "/v2/#{account_id}/templates/#{template}/records/#{record_id}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "deleteTemplateRecord rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, template, record_id} <- [
            {"1010", "offline-template", 1},
            {nil, "offline-template", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "offline-template", "1"},
            {1010, "offline-template", nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.TemplateRecord.delete(
                   request,
                   account_id,
                   template,
                   record_id
                 )
      end

      refute_received {:request, _request}
    end

    test "deleteTemplateRecord preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["cannot be deleted"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.TemplateRecord.delete(
                   client(status, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(
          :delete,
          "/v2/1010/templates/offline-template/records/1",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "deleteTemplateRecord rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.TemplateRecord.delete(
                   client(status, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(
          :delete,
          "/v2/1010/templates/offline-template/records/1",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "deleteTemplateRecord preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.TemplateRecord.delete(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template",
                 1
               )
    end
  end

  defp template_record_body(priority) do
    %{
      "data" => %{
        "id" => 1,
        "template_id" => 1,
        "name" => "",
        "content" => "mail.{{domain}}",
        "ttl" => 0,
        "priority" => priority,
        "type" => "MX",
        "created_at" => "2026-09-01T10:00:00+02:00",
        "updated_at" => "2026-09-01T10:00:00+02:00"
      }
    }
  end

  defp page_client(pages, headers \\ %{}) do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:request, request})
      page = request.url.query |> URI.decode_query() |> Map.fetch!("page") |> String.to_integer()

      case Map.fetch!(pages, page) do
        {:error, reason} ->
          {request, %Req.TransportError{reason: reason}}

        {status, body} ->
          {request,
           Req.Response.new(status: status, body: body, headers: Map.get(headers, page, []))}
      end
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
