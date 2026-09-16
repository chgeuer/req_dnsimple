defmodule ReqDnsimple.TemplateTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  test "template data, bodyless successes, and HTTP errors retain response headers" do
    headers = [
      {"x-ratelimit-remaining", "0"},
      {"x-request-id", "template-response"},
      {"retry-after", "120"}
    ]

    assert {:ok,
            {%ReqDnsimple.Template{id: 1},
             %ReqDnsimple.Metadata{
               status: 200,
               rate_limit_remaining: 0,
               request_id: "template-response"
             }}} =
             ReqDnsimple.Template.get(
               client(200, template_body(), self(), headers),
               1010,
               "offline-template"
             )

    assert_request(:get, "/v2/1010/templates/offline-template")

    for {operation, method, path} <- [
          {&ReqDnsimple.Template.apply(&1, 1010, "example.test", "offline-template"), :post,
           "/v2/1010/domains/example.test/templates/offline-template"},
          {&ReqDnsimple.Template.delete(&1, 1010, "offline-template"), :delete,
           "/v2/1010/templates/offline-template"}
        ] do
      assert {:ok,
              {nil,
               %ReqDnsimple.Metadata{
                 status: 204,
                 rate_limit_remaining: 0,
                 request_id: "template-response"
               }}} = operation.(client(204, nil, self(), headers))

      assert_request(method, path)
    end

    assert {:error,
            %ReqDnsimple.Error{
              reason: reason,
              metadata: %ReqDnsimple.Metadata{
                status: 429,
                rate_limit_remaining: 0,
                request_id: "template-response",
                retry_after: "120"
              }
            }} =
             ReqDnsimple.Template.get(
               client(429, %{"message" => "rate limited"}, self(), headers),
               1010,
               "offline-template"
             )

    assert reason.status == 429
    refute Map.has_key?(reason, :retry_after)
    assert_request(:get, "/v2/1010/templates/offline-template")
    refute_received {:request, _request}
  end

  describe "list_page/3 and list/3" do
    test "listTemplates sends ordered options once and returns typed data" do
      pagination = %{
        "current_page" => 2,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      templates = [
        template_body()["data"],
        template_body()["data"] |> Map.put("id", 2) |> Map.put("sid", "second-template")
      ]

      assert {:ok,
              {[
                 %ReqDnsimple.Template{
                   id: 1,
                   account_id: 1010,
                   name: "Offline template",
                   sid: "offline-template",
                   description: "Offline example",
                   created_at: ~U[2026-09-01 08:00:00Z],
                   updated_at: ~U[2026-09-01 08:30:00Z]
                 },
                 %ReqDnsimple.Template{id: 2, sid: "second-template"}
               ], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.Template.list_page(
                 client(200, %{"data" => templates, "pagination" => pagination}),
                 1010,
                 sort: [id: :asc, name: :desc, sid: :asc],
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/templates",
        %{"sort" => "id:asc,name:desc,sid:asc", "page" => 2, "per_page" => 1},
        nil
      )

      refute_received {:request, _request}
    end

    test "listTemplates alias requests one empty page without adding defaults" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 0,
        "total_pages" => 0
      }

      assert {:ok, {[], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.Template.list(
                 client(200, %{"data" => [], "pagination" => pagination}),
                 0
               )

      assert_request(:get, "/v2/0/templates", %{}, nil)
      refute_received {:request, _request}
    end

    test "listTemplates rejects invalid paths and options before HTTP" do
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

      for {account_id, opts} <- [
            {"1010", []},
            {nil, []},
            {1010, [:invalid]},
            {1010, [{:name}]},
            {1010, [unknown: true]},
            {1010, [sort: "id:asc"]},
            {1010, [sort: [created_at: :asc]]},
            {1010, [sort: [id: :sideways]]},
            {1010, [page: 0]},
            {1010, [per_page: 0]},
            {1010, [per_page: 101]}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Template.list_page(request, account_id, opts)
      end

      refute_received {:request, _request}
    end

    test "listTemplates preserves HTTP and transport failures" do
      for status <- [401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template" => ["is unavailable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.list_page(client(status, body), 1010)

        assert_request(:get, "/v2/1010/templates", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Template.list_page(transport_error_client(:timeout), 1010)
    end

    test "listTemplates rejects malformed successful responses" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      template = template_body()["data"]

      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => pagination},
        %{"data" => %{}, "pagination" => pagination},
        %{"data" => [Map.delete(template, "description")], "pagination" => pagination},
        %{"data" => [Map.put(template, "description", nil)], "pagination" => pagination},
        %{"data" => [Map.put(template, "created_at", "invalid")], "pagination" => pagination}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Template.list_page(client(200, body), 1010)

        assert_request(:get, "/v2/1010/templates", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  test "listTemplates preserves business data when pagination metadata is absent or malformed" do
    pagination = %{
      "current_page" => 1,
      "per_page" => 30,
      "total_entries" => 1,
      "total_pages" => 1
    }

    template = template_body()["data"]
    incomplete = Map.delete(pagination, "total_entries")
    zero_page_size = %{pagination | "per_page" => 0}

    for {body, expected_pagination, expected_errors} <- [
          {%{"data" => [template]}, nil, %{}},
          {%{"data" => [template], "pagination" => nil}, nil, %{}},
          {%{"data" => [template], "pagination" => incomplete}, nil,
           %{pagination: {:invalid_pagination, incomplete}}},
          {%{"data" => [template], "pagination" => zero_page_size}, zero_page_size, %{}}
        ] do
      assert {:ok,
              {[%ReqDnsimple.Template{id: 1}],
               %ReqDnsimple.Metadata{
                 status: 200,
                 pagination: ^expected_pagination,
                 parse_errors: ^expected_errors
               }}} = ReqDnsimple.Template.list_page(client(200, body), 1010)

      assert_request(:get, "/v2/1010/templates", %{}, nil)
      refute_received {:request, _request}
    end
  end

  describe "list_all/3" do
    test "enumerates from page one while preserving options and server order" do
      first = template_body()["data"]
      second = template_body()["data"] |> Map.put("id", 2) |> Map.put("sid", "second-template")

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
                 %ReqDnsimple.Template{id: 1, sid: "offline-template"},
                 %ReqDnsimple.Template{id: 2, sid: "second-template"}
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
               ReqDnsimple.Template.list_all(
                 page_client(pages, headers),
                 1010,
                 sort: [sid: :desc, name: :asc],
                 per_page: 1
               )

      query = %{"sort" => "sid:desc,name:asc", "per_page" => 1}
      assert metadata.parse_errors == %{}
      assert Enum.all?(metadata.pages, &(&1.parse_errors == %{}))

      assert_request(:get, "/v2/1010/templates", Map.put(query, "page", 1))
      assert_request(:get, "/v2/1010/templates", Map.put(query, "page", 2))
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
               ReqDnsimple.Template.list_all(request, 1010, page: 2)

      for opts <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Template.list_all(request, 1010, opts)
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
          1 => {200, %{"data" => [template_body()["data"]], "pagination" => first_page}},
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
               ReqDnsimple.Template.list_all(http_client, 1010)

      assert_request(:get, "/v2/1010/templates", %{"page" => 1})
      assert_request(:get, "/v2/1010/templates", %{"page" => 2})

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
               ReqDnsimple.Template.list_all(
                 page_client(%{
                   1 => {200, %{"data" => [template_body()["data"]], "pagination" => first_page}},
                   2 => {:error, :timeout}
                 }),
                 1010
               )

      assert_request(:get, "/v2/1010/templates", %{"page" => 1})
      assert_request(:get, "/v2/1010/templates", %{"page" => 2})

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
               ReqDnsimple.Template.list_all(
                 page_client(%{
                   1 => {200, %{"data" => [template_body()["data"]], "pagination" => first_page}},
                   2 => {200, %{"data" => [template_body()["data"]], "pagination" => first_page}}
                 }),
                 1010
               )

      assert_request(:get, "/v2/1010/templates", %{"page" => 1})
      assert_request(:get, "/v2/1010/templates", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "create/3" do
    test "createTemplate sends all attributes once and returns the typed template" do
      assert {:ok,
              {%ReqDnsimple.Template{
                 id: 1,
                 account_id: 1010,
                 name: "Offline template",
                 sid: "offline-template",
                 description: "Offline example",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Template.create(
                 client(201, template_body()),
                 1010,
                 sid: "offline-template",
                 name: "Offline template",
                 description: "Offline example"
               )

      assert_request(:post, "/v2/1010/templates", %{}, %{
        "sid" => "offline-template",
        "name" => "Offline template",
        "description" => "Offline example"
      })

      refute_received {:request, _request}
    end

    test "createTemplate preserves omitted and explicitly empty descriptions" do
      for {account_id, attrs, expected_body} <- [
            {1010, [sid: "offline-template", name: "Offline template"],
             %{"sid" => "offline-template", "name" => "Offline template"}},
            {0, [sid: "", name: "", description: ""],
             %{"sid" => "", "name" => "", "description" => ""}}
          ] do
        assert {:ok, {%ReqDnsimple.Template{}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Template.create(client(201, template_body()), account_id, attrs)

        assert_request(:post, "/v2/#{account_id}/templates", %{}, expected_body)
        refute_received {:request, _request}
      end
    end

    test "createTemplate rejects invalid attributes before HTTP" do
      request = client(201, template_body())

      for {account_id, attrs} <- [
            {"1010", [sid: "offline-template", name: "Offline template"]},
            {nil, [sid: "offline-template", name: "Offline template"]},
            {1010, [:invalid]},
            {1010, [{:name}]},
            {1010, []},
            {1010, [name: "Offline template"]},
            {1010, [sid: "offline-template"]},
            {1010, [sid: nil, name: "Offline template"]},
            {1010, [sid: false, name: "Offline template"]},
            {1010, [sid: 0, name: "Offline template"]},
            {1010, [sid: [], name: "Offline template"]},
            {1010, [sid: %{}, name: "Offline template"]},
            {1010, [sid: "offline-template", name: nil]},
            {1010, [sid: "offline-template", name: false]},
            {1010, [sid: "offline-template", name: 0]},
            {1010, [sid: "offline-template", name: []]},
            {1010, [sid: "offline-template", name: %{}]},
            {1010, [sid: "offline-template", name: "Offline template", description: nil]},
            {1010, [sid: "offline-template", name: "Offline template", description: false]},
            {1010, [sid: "offline-template", name: "Offline template", description: 0]},
            {1010, [sid: "offline-template", name: "Offline template", description: []]},
            {1010, [sid: "offline-template", name: "Offline template", description: %{}]},
            {1010, [sid: "offline-template", name: "Offline template", unknown: true]}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Template.create(request, account_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "createTemplate preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"sid" => ["has already been taken"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.create(
                   client(status, body),
                   1010,
                   sid: "offline-template",
                   name: "Offline template"
                 )

        assert_request(:post, "/v2/1010/templates", %{}, %{
          "sid" => "offline-template",
          "name" => "Offline template"
        })

        refute_received {:request, _request}
      end
    end

    test "createTemplate rejects malformed successful responses and unexpected statuses" do
      malformed_responses = [
        {201, %{}},
        {201, %{"data" => nil}},
        {201, %{"data" => Map.delete(template_body()["data"], "name")}},
        {201, put_in(template_body(), ["data", "description"], nil)},
        {201, put_in(template_body(), ["data", "created_at"], "not-a-timestamp")},
        {200, template_body()}
      ]

      for {status, body} <- malformed_responses do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.create(
                   client(status, body),
                   1010,
                   sid: "offline-template",
                   name: "Offline template"
                 )

        assert_request(:post, "/v2/1010/templates", %{}, %{
          "sid" => "offline-template",
          "name" => "Offline template"
        })

        refute_received {:request, _request}
      end
    end

    test "createTemplate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Template.create(
                 transport_error_client(:timeout),
                 1010,
                 sid: "offline-template",
                 name: "Offline template"
               )
    end
  end

  describe "update/4" do
    test "updateTemplate patches all attributes at the original identifier and returns typed data" do
      assert {:ok,
              {%ReqDnsimple.Template{
                 id: 1,
                 account_id: 1010,
                 name: "Offline template",
                 sid: "offline-template",
                 description: "Offline example",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Template.update(
                 client(200, template_body()),
                 1010,
                 "current-template",
                 sid: "offline-template",
                 name: "Offline template",
                 description: "Offline example"
               )

      assert_request(:patch, "/v2/1010/templates/current-template", %{}, %{
        "sid" => "offline-template",
        "name" => "Offline template",
        "description" => "Offline example"
      })

      refute_received {:request, _request}
    end

    test "updateTemplate preserves omitted and explicitly empty fields" do
      for {account_id, template, attrs, expected_body} <- [
            {1010, "offline-template", [description: ""], %{"description" => ""}},
            {0, 0, [sid: "", name: "", description: ""],
             %{"sid" => "", "name" => "", "description" => ""}},
            {1010, 42, [], %{}}
          ] do
        assert {:ok, {%ReqDnsimple.Template{}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Template.update(
                   client(200, template_body()),
                   account_id,
                   template,
                   attrs
                 )

        assert_request(:patch, "/v2/#{account_id}/templates/#{template}", %{}, expected_body)
        refute_received {:request, _request}
      end
    end

    test "updateTemplate rejects invalid paths and attributes before HTTP" do
      request = client(200, template_body())

      invalid_cases =
        [
          {"1010", "offline-template", [description: "Updated"]},
          {nil, "offline-template", [description: "Updated"]},
          {1010, nil, [description: "Updated"]},
          {1010, 1.5, [description: "Updated"]},
          {1010, [], [description: "Updated"]},
          {1010, %{}, [description: "Updated"]},
          {1010, "offline-template", [:invalid]},
          {1010, "offline-template", [{:name}]},
          {1010, "offline-template", [unknown: true]}
        ] ++
          for field <- [:sid, :name, :description],
              value <- [nil, false, 0, [], %{}] do
            {1010, "offline-template", [{field, value}]}
          end

      for {account_id, template, attrs} <- invalid_cases do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Template.update(request, account_id, template, attrs)
      end

      refute_received {:request, _request}
    end

    test "updateTemplate preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"sid" => ["has already been taken"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.update(
                   client(status, body),
                   1010,
                   "offline-template",
                   description: "Updated"
                 )

        assert_request(:patch, "/v2/1010/templates/offline-template", %{}, %{
          "description" => "Updated"
        })

        refute_received {:request, _request}
      end
    end

    test "updateTemplate rejects malformed successful responses and unexpected statuses" do
      malformed_responses = [
        {200, %{}},
        {200, %{"data" => nil}},
        {200, %{"data" => Map.delete(template_body()["data"], "name")}},
        {200, put_in(template_body(), ["data", "description"], nil)},
        {200, put_in(template_body(), ["data", "created_at"], "not-a-timestamp")},
        {201, template_body()}
      ]

      for {status, body} <- malformed_responses do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.update(
                   client(status, body),
                   1010,
                   "offline-template",
                   description: "Updated"
                 )

        assert_request(:patch, "/v2/1010/templates/offline-template", %{}, %{
          "description" => "Updated"
        })

        refute_received {:request, _request}
      end
    end

    test "updateTemplate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Template.update(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template",
                 description: "Updated"
               )
    end
  end

  describe "get/3" do
    test "getTemplate retrieves one typed template with one bodyless request" do
      body = template_body()

      assert {:ok,
              {%ReqDnsimple.Template{
                 id: 1,
                 account_id: 1010,
                 name: "Offline template",
                 sid: "offline-template",
                 description: "Offline example",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Template.get(client(200, body), 1010, "offline-template")

      assert_request(:get, "/v2/1010/templates/offline-template", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTemplate accepts integer, zero, and empty template identifiers" do
      body = template_body()

      for {account_id, template} <- [{1010, 42}, {0, 0}, {1010, ""}] do
        assert {:ok, {%ReqDnsimple.Template{}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Template.get(client(200, body), account_id, template)

        assert_request(:get, "/v2/#{account_id}/templates/#{template}", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplate rejects invalid path parameters before HTTP" do
      request = client(200, template_body())

      for {account_id, template} <- [
            {"1010", "offline-template"},
            {nil, "offline-template"},
            {1010, nil},
            {1010, 1.5},
            {1010, []},
            {1010, %{}}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Template.get(request, account_id, template)
      end

      refute_received {:request, _request}
    end

    test "getTemplate rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(template_body(), ["data", "created_at"], "not-a-timestamp"),
        put_in(template_body(), ["data", "account_id"], "1010"),
        put_in(template_body(), ["data", "description"], nil)
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Template.get(client(200, body), 1010, "offline-template")

        assert_request(:get, "/v2/1010/templates/offline-template", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplate preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template" => ["was not found"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.get(client(status, body), 1010, "offline-template")

        assert_request(:get, "/v2/1010/templates/offline-template", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Template.get(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template"
               )
    end
  end

  describe "apply/4" do
    test "applyTemplateToDomain sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Template.apply(
                 client(204, nil),
                 1010,
                 "example.test",
                 "offline-template"
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/templates/offline-template",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "applyTemplateToDomain accepts integer, zero, and empty identifiers" do
      for {account_id, domain, template} <- [{0, 0, 0}, {1010, "", ""}] do
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
                 ReqDnsimple.Template.apply(
                   client(204, nil),
                   account_id,
                   domain,
                   template
                 )

        assert_request(
          :post,
          "/v2/#{account_id}/domains/#{domain}/templates/#{template}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyTemplateToDomain rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, domain, template} <- [
            {"1010", "example.test", "offline-template"},
            {nil, "example.test", "offline-template"},
            {1010, nil, "offline-template"},
            {1010, 1.5, "offline-template"},
            {1010, "example.test", nil},
            {1010, "example.test", 1.5}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Template.apply(request, account_id, domain, template)
      end

      refute_received {:request, _request}
    end

    test "applyTemplateToDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template" => ["cannot be applied"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.apply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-template"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/templates/offline-template",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyTemplateToDomain rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.apply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-template"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/templates/offline-template",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyTemplateToDomain preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Template.apply(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 "offline-template"
               )
    end
  end

  describe "delete/3" do
    test "deleteTemplate sends one bodyless request and returns nil data with metadata" do
      assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
               ReqDnsimple.Template.delete(
                 client(204, nil),
                 1010,
                 "offline-template"
               )

      assert_request(:delete, "/v2/1010/templates/offline-template", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteTemplate accepts integer, zero, and empty template identifiers" do
      for {account_id, template} <- [{1010, 42}, {0, 0}, {1010, ""}] do
        assert {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}} =
                 ReqDnsimple.Template.delete(client(204, nil), account_id, template)

        assert_request(:delete, "/v2/#{account_id}/templates/#{template}", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteTemplate rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, template} <- [
            {"1010", "offline-template"},
            {nil, "offline-template"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Template.delete(request, account_id, template)
      end

      refute_received {:request, _request}
    end

    test "deleteTemplate preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template" => ["cannot be deleted"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.delete(
                   client(status, body),
                   1010,
                   "offline-template"
                 )

        assert_request(:delete, "/v2/1010/templates/offline-template", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteTemplate rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Template.delete(
                   client(status, body),
                   1010,
                   "offline-template"
                 )

        assert_request(:delete, "/v2/1010/templates/offline-template", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteTemplate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Template.delete(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template"
               )
    end
  end

  defp template_body do
    %{
      "data" => %{
        "id" => 1,
        "account_id" => 1010,
        "name" => "Offline template",
        "sid" => "offline-template",
        "description" => "Offline example",
        "created_at" => "2026-09-01T10:00:00+02:00",
        "updated_at" => "2026-09-01T10:30:00+02:00"
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
