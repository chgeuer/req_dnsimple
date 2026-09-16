defmodule ReqDnsimple.ServiceTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  test "service data, bodyless successes, and HTTP errors retain response headers" do
    headers = [
      {"x-ratelimit-remaining", "0"},
      {"x-request-id", "service-response"},
      {"retry-after", "120"}
    ]

    assert {:ok,
            {%ReqDnsimple.Service{id: 1},
             %ReqDnsimple.Metadata{
               status: 200,
               rate_limit_remaining: 0,
               request_id: "service-response"
             }}} =
             ReqDnsimple.Service.get(
               client(200, service_body(), self(), headers),
               "offline-service"
             )

    assert_request(:get, "/v2/services/offline-service")

    for {operation, method} <- [
          {&ReqDnsimple.Service.apply(&1, 1010, "example.test", "offline-service"), :post},
          {&ReqDnsimple.Service.unapply(&1, 1010, "example.test", "offline-service"), :delete}
        ] do
      assert {:ok,
              {nil,
               %ReqDnsimple.Metadata{
                 status: 204,
                 rate_limit_remaining: 0,
                 request_id: "service-response"
               }}} = operation.(client(204, nil, self(), headers))

      assert_request(method, "/v2/1010/domains/example.test/services/offline-service")
    end

    assert {:error,
            %ReqDnsimple.Error{
              reason: reason,
              metadata: %ReqDnsimple.Metadata{
                status: 429,
                rate_limit_remaining: 0,
                request_id: "service-response",
                retry_after: "120"
              }
            }} =
             ReqDnsimple.Service.get(
               client(429, %{"message" => "rate limited"}, self(), headers),
               "offline-service"
             )

    assert reason.status == 429
    refute Map.has_key?(reason, :retry_after)
    assert_request(:get, "/v2/services/offline-service")
    refute_received {:request, _request}
  end

  describe "get/2" do
    test "getService retrieves one typed service with nullable nested fields" do
      body = %{
        "data" => %{
          "id" => 1,
          "name" => "Offline service",
          "sid" => "offline-service",
          "description" => "Offline example",
          "setup_description" => nil,
          "requires_setup" => true,
          "default_subdomain" => nil,
          "created_at" => "2026-09-01T10:00:00+02:00",
          "updated_at" => "2026-09-01T10:30:00+02:00",
          "settings" => [
            %{
              "name" => "example.test",
              "label" => "Offline example",
              "append" => nil,
              "description" => "Offline example",
              "example" => nil,
              "password" => true
            }
          ]
        }
      }

      assert {:ok,
              {%ReqDnsimple.Service{
                 id: 1,
                 name: "Offline service",
                 sid: "offline-service",
                 description: "Offline example",
                 setup_description: nil,
                 requires_setup: true,
                 default_subdomain: nil,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z],
                 settings: [
                   %ReqDnsimple.Service.Setting{
                     name: "example.test",
                     label: "Offline example",
                     append: nil,
                     description: "Offline example",
                     example: nil,
                     password: true
                   }
                 ]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Service.get(client(200, body), "offline-service")

      assert_request(:get, "/v2/services/offline-service", %{}, nil)
      refute_received {:request, _request}
    end

    test "getService accepts integer, zero, and empty identifiers" do
      body = service_body()

      for service <- [12, 0, ""] do
        assert {:ok, {%ReqDnsimple.Service{}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Service.get(client(200, body), service)

        assert_request(:get, "/v2/services/#{service}", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getService rejects invalid identifiers before HTTP" do
      request = client(200, service_body())

      for service <- [nil, 1.5, [], %{}] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Service.get(request, service)
      end

      refute_received {:request, _request}
    end

    test "getService rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(service_body(), ["data", "created_at"], "not-a-timestamp"),
        put_in(service_body(), ["data", "settings"], [%{"name" => "incomplete"}]),
        put_in(service_body(), ["data", "requires_setup"], 0)
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Service.get(client(200, body), "offline-service")

        assert_request(:get, "/v2/services/offline-service", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getService preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"service" => ["was not found"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Service.get(client(status, body), "offline-service")

        assert_request(:get, "/v2/services/offline-service", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getService preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Service.get(transport_error_client(:timeout), "offline-service")
    end
  end

  describe "list_page/2 and list/2" do
    test "listServices sends supported query options once and decodes typed data" do
      pagination = %{
        "current_page" => 2,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      data =
        Map.merge(service_data(), %{
          "requires_setup" => true,
          "default_subdomain" => nil,
          "created_at" => "2026-09-01T10:00:00+02:00",
          "settings" => [
            %{
              "name" => "example.test",
              "label" => "Offline example",
              "append" => nil,
              "description" => "Offline example",
              "example" => nil,
              "password" => false
            }
          ]
        })

      assert {:ok,
              {[
                 %ReqDnsimple.Service{
                   id: 1,
                   setup_description: nil,
                   requires_setup: true,
                   default_subdomain: nil,
                   created_at: ~U[2026-09-01 08:00:00Z],
                   settings: [
                     %ReqDnsimple.Service.Setting{
                       append: nil,
                       example: nil,
                       password: false
                     }
                   ]
                 }
               ], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.Service.list_page(
                 client(200, %{"data" => [data], "pagination" => pagination}),
                 sort: [id: :asc, sid: :desc],
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/services",
        %{"sort" => "id:asc,sid:desc", "page" => 2, "per_page" => 1},
        nil
      )

      refute_received {:request, _request}
    end

    test "listServices alias requests one empty page without materializing defaults" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 0,
        "total_pages" => 0
      }

      assert {:ok, {[], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.Service.list(client(200, %{"data" => [], "pagination" => pagination}))

      assert_request(:get, "/v2/services", %{}, nil)
      refute_received {:request, _request}
    end

    test "listServices rejects invalid options before HTTP" do
      request = client(200, %{})

      invalid_options = [
        [:invalid],
        [{:name}],
        [unknown: true],
        [page: 0],
        [per_page: 0],
        [per_page: 101],
        [sort: [name: :asc]],
        [sort: [id: :up]],
        [sort: "id:asc"]
      ]

      for opts <- invalid_options do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Service.list_page(request, opts)
      end

      refute_received {:request, _request}
    end

    test "listServices preserves HTTP and transport failures" do
      for status <- [401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"service" => ["was not found"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Service.list_page(client(status, body))

        assert_request(:get, "/v2/services", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Service.list_page(transport_error_client(:timeout))
    end

    test "listServices rejects malformed successful responses" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => pagination},
        %{"data" => %{}, "pagination" => pagination},
        %{"data" => [Map.delete(service_data(), "settings")], "pagination" => pagination}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Service.list_page(client(200, body))

        assert_request(:get, "/v2/services", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  test "service collections preserve business data when pagination metadata is absent or malformed" do
    pagination = %{
      "current_page" => 1,
      "per_page" => 30,
      "total_entries" => 1,
      "total_pages" => 1
    }

    incomplete = Map.delete(pagination, "total_entries")
    zero_page_size = %{pagination | "per_page" => 0}

    for {operation, path} <- [
          {&ReqDnsimple.Service.list_page/1, "/v2/services"},
          {&ReqDnsimple.Service.list_page_applied(&1, 1010, "example.test"),
           "/v2/1010/domains/example.test/services"}
        ],
        {body, expected_pagination, expected_errors} <- [
          {%{"data" => [service_data()]}, nil, %{}},
          {%{"data" => [service_data()], "pagination" => nil}, nil, %{}},
          {%{"data" => [service_data()], "pagination" => incomplete}, nil,
           %{pagination: {:invalid_pagination, incomplete}}},
          {%{"data" => [service_data()], "pagination" => zero_page_size}, zero_page_size, %{}}
        ] do
      assert {:ok,
              {[%ReqDnsimple.Service{id: 1}],
               %ReqDnsimple.Metadata{
                 status: 200,
                 pagination: ^expected_pagination,
                 parse_errors: ^expected_errors
               }}} = operation.(client(200, body))

      assert_request(:get, path, %{}, nil)
      refute_received {:request, _request}
    end
  end

  describe "list_all/2" do
    test "enumerates from page one while preserving sorting, page size, and server order" do
      second = Map.put(service_data(), "id", 2)

      pages = %{
        1 =>
          {[service_data()],
           %{
             "current_page" => 1,
             "per_page" => 1,
             "total_entries" => 2,
             "total_pages" => 2
           }},
        2 =>
          {[second],
           %{
             "current_page" => 2,
             "per_page" => 1,
             "total_entries" => 2,
             "total_pages" => 2
           }}
      }

      first_pagination = elem(pages[1], 1)
      second_pagination = elem(pages[2], 1)

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
              {[%ReqDnsimple.Service{id: 1}, %ReqDnsimple.Service{id: 2}],
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
               ReqDnsimple.Service.list_all(
                 service_page_client(pages, headers),
                 sort: [:id, sid: :desc],
                 per_page: 1
               )

      assert metadata.parse_errors == %{}
      assert Enum.all?(metadata.pages, &(&1.parse_errors == %{}))

      assert_request(
        :get,
        "/v2/services",
        %{"sort" => "id:asc,sid:desc", "page" => 1, "per_page" => 1}
      )

      assert_request(
        :get,
        "/v2/services",
        %{"sort" => "id:asc,sid:desc", "page" => 2, "per_page" => 1}
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{})

      assert {:error, %ReqDnsimple.Error{reason: {:invalid_option, :page}, metadata: nil}} =
               ReqDnsimple.Service.list_all(request, page: 2)

      for opts <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Service.list_all(request, opts)
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
        service_response_client(fn
          1 -> {200, %{"data" => [service_data()], "pagination" => first_page}}
          2 -> {503, %{"message" => "unavailable"}}
        end)

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
               ReqDnsimple.Service.list_all(http_client)

      assert_request(:get, "/v2/services", %{"page" => 1})
      assert_request(:get, "/v2/services", %{"page" => 2})

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
               ReqDnsimple.Service.list_all(
                 service_response_client(fn
                   1 -> {200, %{"data" => [service_data()], "pagination" => first_page}}
                   2 -> {:error, :timeout}
                 end)
               )

      repeated = %{first_page | "current_page" => 1}

      assert {:error,
              %ReqDnsimple.Error{
                reason: {:invalid_pagination, ^repeated},
                metadata: %ReqDnsimple.Metadata{
                  status: 200,
                  pagination: ^repeated,
                  pages: [
                    %ReqDnsimple.Metadata{status: 200, pagination: ^repeated, pages: []},
                    %ReqDnsimple.Metadata{status: 200, pagination: ^repeated, pages: []}
                  ]
                }
              }} =
               ReqDnsimple.Service.list_all(
                 service_response_client(fn _page ->
                   {200, %{"data" => [service_data()], "pagination" => repeated}}
                 end)
               )
    end
  end

  describe "list_page_applied/4 and list_applied/4" do
    test "listDomainAppliedServices sends supported query options once and decodes typed data" do
      pagination = %{
        "current_page" => 2,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      data =
        Map.merge(service_data(), %{
          "requires_setup" => true,
          "default_subdomain" => nil,
          "created_at" => "2026-09-01T10:00:00+02:00",
          "settings" => [
            %{
              "name" => "example.test",
              "label" => "Offline example",
              "append" => nil,
              "description" => "Offline example",
              "example" => nil,
              "password" => true
            }
          ]
        })

      assert {:ok,
              {[
                 %ReqDnsimple.Service{
                   id: 1,
                   setup_description: nil,
                   requires_setup: true,
                   default_subdomain: nil,
                   created_at: ~U[2026-09-01 08:00:00Z],
                   settings: [
                     %ReqDnsimple.Service.Setting{
                       append: nil,
                       example: nil,
                       password: true
                     }
                   ]
                 }
               ], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.Service.list_page_applied(
                 client(200, %{"data" => [data], "pagination" => pagination}),
                 1010,
                 "example.test",
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/services",
        %{"page" => 2, "per_page" => 1},
        nil
      )

      refute_received {:request, _request}
    end

    test "listDomainAppliedServices alias requests one empty page without materializing defaults" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 0,
        "total_pages" => 0
      }

      assert {:ok, {[], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.Service.list_applied(
                 client(200, %{"data" => [], "pagination" => pagination}),
                 0,
                 0
               )

      assert_request(:get, "/v2/0/domains/0/services", %{}, nil)
      refute_received {:request, _request}
    end

    test "listDomainAppliedServices accepts empty domain identifiers" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      assert {:ok,
              {[%ReqDnsimple.Service{}],
               %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.Service.list_page_applied(
                 client(200, %{"data" => [service_data()], "pagination" => pagination}),
                 1010,
                 ""
               )

      assert_request(:get, "/v2/1010/domains//services", %{}, nil)
      refute_received {:request, _request}
    end

    test "listDomainAppliedServices rejects invalid paths and options before HTTP" do
      request = client(200, %{})

      invalid_calls = [
        {"1010", "example.test", []},
        {nil, "example.test", []},
        {1010, nil, []},
        {1010, 1.5, []},
        {1010, [], []},
        {1010, "example.test", [:invalid]},
        {1010, "example.test", [{:name}]},
        {1010, "example.test", [unknown: true]},
        {1010, "example.test", [page: 0]},
        {1010, "example.test", [per_page: 0]},
        {1010, "example.test", [per_page: 101]}
      ]

      for {account_id, domain, opts} <- invalid_calls do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Service.list_page_applied(request, account_id, domain, opts)
      end

      refute_received {:request, _request}
    end

    test "listDomainAppliedServices preserves HTTP and transport failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["was not found"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Service.list_page_applied(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/example.test/services", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Service.list_page_applied(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end

    test "listDomainAppliedServices rejects malformed successful responses" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => pagination},
        %{"data" => %{}, "pagination" => pagination},
        %{"data" => [Map.delete(service_data(), "settings")], "pagination" => pagination}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Service.list_page_applied(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/example.test/services", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  describe "list_all_applied/4" do
    test "enumerates from page one while preserving page size and server order" do
      second = Map.put(service_data(), "id", 2)

      pages = %{
        1 =>
          {[service_data()],
           %{
             "current_page" => 1,
             "per_page" => 1,
             "total_entries" => 2,
             "total_pages" => 2
           }},
        2 =>
          {[second],
           %{
             "current_page" => 2,
             "per_page" => 1,
             "total_entries" => 2,
             "total_pages" => 2
           }}
      }

      first_pagination = elem(pages[1], 1)
      second_pagination = elem(pages[2], 1)

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
              {[%ReqDnsimple.Service{id: 1}, %ReqDnsimple.Service{id: 2}],
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
               ReqDnsimple.Service.list_all_applied(
                 service_page_client(pages, headers),
                 1010,
                 "example.test",
                 per_page: 1
               )

      assert metadata.parse_errors == %{}
      assert Enum.all?(metadata.pages, &(&1.parse_errors == %{}))

      assert_request(
        :get,
        "/v2/1010/domains/example.test/services",
        %{"page" => 1, "per_page" => 1}
      )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/services",
        %{"page" => 2, "per_page" => 1}
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{})

      assert {:error, %ReqDnsimple.Error{reason: {:invalid_option, :page}, metadata: nil}} =
               ReqDnsimple.Service.list_all_applied(
                 request,
                 1010,
                 "example.test",
                 page: 2
               )

      for opts <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Service.list_all_applied(
                   request,
                   1010,
                   "example.test",
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
        service_response_client(fn
          1 -> {200, %{"data" => [service_data()], "pagination" => first_page}}
          2 -> {503, %{"message" => "unavailable"}}
        end)

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
               ReqDnsimple.Service.list_all_applied(http_client, 1010, "example.test")

      assert_request(:get, "/v2/1010/domains/example.test/services", %{"page" => 1})
      assert_request(:get, "/v2/1010/domains/example.test/services", %{"page" => 2})

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
               ReqDnsimple.Service.list_all_applied(
                 service_response_client(fn
                   1 -> {200, %{"data" => [service_data()], "pagination" => first_page}}
                   2 -> {:error, :timeout}
                 end),
                 1010,
                 "example.test"
               )

      repeated = %{first_page | "current_page" => 1}

      assert {:error,
              %ReqDnsimple.Error{
                reason: {:invalid_pagination, ^repeated},
                metadata: %ReqDnsimple.Metadata{
                  status: 200,
                  pagination: ^repeated,
                  pages: [
                    %ReqDnsimple.Metadata{status: 200, pagination: ^repeated, pages: []},
                    %ReqDnsimple.Metadata{status: 200, pagination: ^repeated, pages: []}
                  ]
                }
              }} =
               ReqDnsimple.Service.list_all_applied(
                 service_response_client(fn _page ->
                   {200, %{"data" => [service_data()], "pagination" => repeated}}
                 end),
                 1010,
                 "example.test"
               )
    end
  end

  describe "apply/4 and apply/5" do
    test "applyServiceToDomain sends one request with string-keyed settings and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Service.apply(
                 client(204, ""),
                 1010,
                 "example.test",
                 "offline-service",
                 settings: %{
                   "app" => "fake-offline-app",
                   "enabled" => false,
                   "priority" => 0,
                   "aliases" => [],
                   "metadata" => %{},
                   "note" => ""
                 }
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/services/offline-service",
        %{},
        %{
          settings: %{
            "app" => "fake-offline-app",
            "enabled" => false,
            "priority" => 0,
            "aliases" => [],
            "metadata" => %{},
            "note" => ""
          }
        }
      )

      refute_received {:request, _request}
    end

    test "applyServiceToDomain distinguishes omitted settings from an explicit empty object" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Service.apply(
                 client(204, nil),
                 1010,
                 "example.test",
                 "offline-service"
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/services/offline-service",
        %{},
        nil
      )

      refute_received {:request, _request}

      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Service.apply(
                 client(204, nil),
                 1010,
                 "example.test",
                 "offline-service",
                 settings: %{}
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/services/offline-service",
        %{},
        %{settings: %{}}
      )

      refute_received {:request, _request}
    end

    test "applyServiceToDomain accepts integer, zero, and empty identifiers" do
      for {account_id, domain, service} <- [{0, 0, 0}, {1010, "", ""}] do
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
                 ReqDnsimple.Service.apply(
                   client(204, nil),
                   account_id,
                   domain,
                   service
                 )

        assert_request(
          :post,
          "/v2/#{account_id}/domains/#{domain}/services/#{service}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyServiceToDomain rejects invalid paths and attributes before HTTP" do
      request = client(204, nil)

      invalid_calls = [
        {"1010", "example.test", "offline-service", []},
        {nil, "example.test", "offline-service", []},
        {1010, nil, "offline-service", []},
        {1010, 1.5, "offline-service", []},
        {1010, "example.test", nil, []},
        {1010, "example.test", 1.5, []},
        {1010, "example.test", "offline-service", [settings: nil]},
        {1010, "example.test", "offline-service", [settings: []]},
        {1010, "example.test", "offline-service", [settings: %{app: "fake"}]},
        {1010, "example.test", "offline-service", [unknown: true]},
        {1010, "example.test", "offline-service", [:invalid]},
        {1010, "example.test", "offline-service", [{:name}]},
        {1010, "example.test", "offline-service", %{settings: %{}}}
      ]

      for {account_id, domain, service, attrs} <- invalid_calls do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Service.apply(request, account_id, domain, service, attrs)
      end

      refute_received {:request, _request}
    end

    test "applyServiceToDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"settings" => ["are invalid"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Service.apply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-service"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/services/offline-service",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyServiceToDomain rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Service.apply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-service"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/services/offline-service",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyServiceToDomain preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Service.apply(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 "offline-service"
               )
    end
  end

  describe "unapply/4" do
    test "unapplyServiceFromDomain sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Service.unapply(
                 client(204, ""),
                 1010,
                 "example.test",
                 "offline-service"
               )

      assert_request(
        :delete,
        "/v2/1010/domains/example.test/services/offline-service",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "unapplyServiceFromDomain accepts integer, zero, and empty identifiers" do
      for {account_id, domain, service} <- [{0, 0, 0}, {1010, "", ""}] do
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
                 ReqDnsimple.Service.unapply(
                   client(204, nil),
                   account_id,
                   domain,
                   service
                 )

        assert_request(
          :delete,
          "/v2/#{account_id}/domains/#{domain}/services/#{service}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "unapplyServiceFromDomain rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, domain, service} <- [
            {"1010", "example.test", "offline-service"},
            {nil, "example.test", "offline-service"},
            {1010, nil, "offline-service"},
            {1010, 1.5, "offline-service"},
            {1010, "example.test", nil},
            {1010, "example.test", 1.5}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Service.unapply(request, account_id, domain, service)
      end

      refute_received {:request, _request}
    end

    test "unapplyServiceFromDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"service" => ["is unavailable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Service.unapply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-service"
                 )

        assert_request(
          :delete,
          "/v2/1010/domains/example.test/services/offline-service",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "unapplyServiceFromDomain rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Service.unapply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-service"
                 )

        assert_request(
          :delete,
          "/v2/1010/domains/example.test/services/offline-service",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "unapplyServiceFromDomain preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Service.unapply(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 "offline-service"
               )
    end
  end

  defp service_body do
    %{"data" => service_data()}
  end

  defp service_data do
    %{
      "id" => 1,
      "name" => "Offline service",
      "sid" => "offline-service",
      "description" => "Offline example",
      "setup_description" => nil,
      "requires_setup" => false,
      "default_subdomain" => "",
      "created_at" => "2026-09-01T10:00:00Z",
      "updated_at" => "2026-09-01T10:30:00Z",
      "settings" => []
    }
  end

  defp service_page_client(pages, headers) do
    service_response_client(fn page ->
      {data, pagination} = Map.fetch!(pages, page)
      {200, %{"data" => data, "pagination" => pagination}, Map.get(headers, page, [])}
    end)
  end

  defp service_response_client(response_for_page) do
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
