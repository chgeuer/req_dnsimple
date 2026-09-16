defmodule ReqDnsimple.TldTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  test "TLD data and HTTP errors retain response headers" do
    headers = [
      {"x-ratelimit-remaining", "0"},
      {"x-request-id", "tld-response"},
      {"retry-after", "120"}
    ]

    assert {:ok,
            {%ReqDnsimple.Tld{tld: "com.au"},
             %ReqDnsimple.Metadata{
               status: 200,
               rate_limit_remaining: 0,
               request_id: "tld-response"
             }}} =
             ReqDnsimple.Tld.get(client(200, tld_body(), self(), headers), "com.au")

    assert_request(:get, "/v2/tlds/com.au")

    assert {:ok,
            {[%ReqDnsimple.Tld.ExtendedAttribute{} | _],
             %ReqDnsimple.Metadata{
               status: 200,
               rate_limit_remaining: 0,
               request_id: "tld-response"
             }}} =
             ReqDnsimple.Tld.list_extended_attributes(
               client(200, extended_attributes_body(), self(), headers),
               "co.uk"
             )

    assert_request(:get, "/v2/tlds/co.uk/extended_attributes")

    assert {:error,
            %ReqDnsimple.Error{
              reason: reason,
              metadata: %ReqDnsimple.Metadata{
                status: 429,
                rate_limit_remaining: 0,
                request_id: "tld-response",
                retry_after: "120"
              }
            }} =
             ReqDnsimple.Tld.get(
               client(429, %{"message" => "rate limited"}, self(), headers),
               "com.au"
             )

    assert reason.status == 429
    refute Map.has_key?(reason, :retry_after)
    assert_request(:get, "/v2/tlds/com.au")
    refute_received {:request, _request}
  end

  describe "get/2" do
    test "getTld retrieves one typed TLD without changing a compound suffix" do
      body = tld_body()

      assert {:ok,
              {%ReqDnsimple.Tld{
                 tld: "com.au",
                 tld_type: 1,
                 whois_privacy: true,
                 auto_renew_only: false,
                 idn: true,
                 minimum_registration: 0,
                 registration_enabled: true,
                 renewal_enabled: true,
                 transfer_enabled: true,
                 dnssec_interface_type: "ds",
                 name_server_min: 2,
                 name_server_max: 13,
                 trustee_service_enabled: false,
                 trustee_service_required: false
               }, %ReqDnsimple.Metadata{}}} = ReqDnsimple.Tld.get(client(200, body), "com.au")

      assert_request(:get, "/v2/tlds/com.au", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTld normalizes numeric-string bounds and preserves missing bounds" do
      string_bounds =
        tld_body()
        |> put_in(["data", "name_server_min"], "002")
        |> put_in(["data", "name_server_max"], "13")

      assert {:ok,
              {%ReqDnsimple.Tld{name_server_min: 2, name_server_max: 13}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Tld.get(client(200, string_bounds), "com.au")

      assert_request(:get, "/v2/tlds/com.au", %{}, nil)

      missing_bounds =
        tld_body()
        |> update_in(["data"], &Map.drop(&1, ["name_server_min", "name_server_max"]))

      assert {:ok,
              {%ReqDnsimple.Tld{name_server_min: nil, name_server_max: nil},
               %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Tld.get(client(200, missing_bounds), "com.au")

      assert_request(:get, "/v2/tlds/com.au", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTld rejects explicit null and signed strings for optional bounds" do
      invalid_bounds = [
        {"name_server_min", nil},
        {"name_server_max", nil},
        {"name_server_min", "+2"},
        {"name_server_min", "-0"},
        {"name_server_max", "+13"},
        {"name_server_max", "-0"}
      ]

      for {field, value} <- invalid_bounds do
        body = put_in(tld_body(), ["data", field], value)

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Tld.get(client(200, body), "com")

        assert_request(:get, "/v2/tlds/com", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTld preserves integer zero bounds" do
      zero_bounds =
        tld_body()
        |> put_in(["data", "name_server_min"], 0)
        |> put_in(["data", "name_server_max"], 0)

      assert {:ok,
              {%ReqDnsimple.Tld{name_server_min: 0, name_server_max: 0}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Tld.get(client(200, zero_bounds), "com")

      assert_request(:get, "/v2/tlds/com", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTld accepts an empty suffix and rejects invalid types before HTTP" do
      assert {:ok, {%ReqDnsimple.Tld{}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Tld.get(client(200, tld_body()), "")

      assert_request(:get, "/v2/tlds/", %{}, nil)

      request = client(200, tld_body())

      for tld <- [nil, 1, 1.5, [], %{}] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Tld.get(request, tld)
      end

      refute_received {:request, _request}
    end

    test "getTld rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(tld_body(), ["data", "tld_type"], 4),
        put_in(tld_body(), ["data", "dnssec_interface_type"], "unsupported"),
        put_in(tld_body(), ["data", "name_server_min"], "2.5"),
        put_in(tld_body(), ["data", "name_server_min"], "2\n"),
        put_in(tld_body(), ["data", "name_server_max"], "13x"),
        put_in(tld_body(), ["data", "whois_privacy"], 1)
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Tld.get(client(200, body), "com")

        assert_request(:get, "/v2/tlds/com", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTld preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"tld" => ["was not found"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Tld.get(client(status, body), "com")

        assert_request(:get, "/v2/tlds/com", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTld preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Tld.get(transport_error_client(:timeout), "com")
    end
  end

  describe "list_page/2 and list/2" do
    test "listTlds sends supported query options once and decodes typed data" do
      pagination = %{
        "current_page" => 2,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      data =
        tld_data()
        |> Map.put("tld", "co.uk")
        |> Map.put("name_server_min", "002")
        |> Map.delete("name_server_max")

      assert {:ok,
              {[
                 %ReqDnsimple.Tld{
                   tld: "co.uk",
                   name_server_min: 2,
                   name_server_max: nil,
                   auto_renew_only: false,
                   minimum_registration: 0,
                   trustee_service_enabled: false
                 }
               ], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.Tld.list_page(
                 client(200, %{"data" => [data], "pagination" => pagination}),
                 sort: [tld: :asc, tld: :desc],
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/tlds",
        %{"sort" => "tld:asc,tld:desc", "page" => 2, "per_page" => 1},
        nil
      )

      refute_received {:request, _request}
    end

    test "listTlds alias requests one empty page without materializing defaults" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 0,
        "total_pages" => 0
      }

      assert {:ok, {[], %ReqDnsimple.Metadata{status: 200, pagination: ^pagination}}} =
               ReqDnsimple.Tld.list(client(200, %{"data" => [], "pagination" => pagination}))

      assert_request(:get, "/v2/tlds", %{}, nil)
      refute_received {:request, _request}
    end

    test "listTlds rejects invalid options before HTTP" do
      request = client(200, %{})

      invalid_options = [
        [:invalid],
        [{:name}],
        [unknown: true],
        [page: 0],
        [per_page: 0],
        [per_page: 101],
        [sort: [name: :asc]],
        [sort: [tld: :up]],
        [sort: "tld:asc"]
      ]

      for opts <- invalid_options do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Tld.list_page(request, opts)
      end

      refute_received {:request, _request}
    end

    test "listTlds rejects malformed successful responses" do
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
        %{"data" => [Map.put(tld_data(), "name_server_min", nil)], "pagination" => pagination},
        %{"data" => [Map.put(tld_data(), "name_server_max", "+13")], "pagination" => pagination},
        %{"data" => [Map.put(tld_data(), "name_server_min", "2x")], "pagination" => pagination},
        %{"data" => [Map.put(tld_data(), "tld_type", 4)], "pagination" => pagination}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Tld.list_page(client(200, body))

        assert_request(:get, "/v2/tlds", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "listTlds preserves HTTP and transport failures" do
      for status <- [401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"tld" => ["was not found"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Tld.list_page(client(status, body))

        assert_request(:get, "/v2/tlds", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Tld.list_page(transport_error_client(:timeout))
    end
  end

  test "listTlds preserves business data when pagination metadata is absent or malformed" do
    pagination = %{
      "current_page" => 1,
      "per_page" => 30,
      "total_entries" => 1,
      "total_pages" => 1
    }

    incomplete = Map.delete(pagination, "total_entries")
    zero_page_size = %{pagination | "per_page" => 0}

    for {body, expected_pagination, expected_errors} <- [
          {%{"data" => [tld_data()]}, nil, %{}},
          {%{"data" => [tld_data()], "pagination" => nil}, nil, %{}},
          {%{"data" => [tld_data()], "pagination" => incomplete}, nil,
           %{pagination: {:invalid_pagination, incomplete}}},
          {%{"data" => [tld_data()], "pagination" => zero_page_size}, zero_page_size, %{}}
        ] do
      assert {:ok,
              {[%ReqDnsimple.Tld{tld: "com.au"}],
               %ReqDnsimple.Metadata{
                 status: 200,
                 pagination: ^expected_pagination,
                 parse_errors: ^expected_errors
               }}} = ReqDnsimple.Tld.list_page(client(200, body))

      assert_request(:get, "/v2/tlds", %{}, nil)
      refute_received {:request, _request}
    end
  end

  describe "list_all/2" do
    test "enumerates from page one while preserving sorting, page size, and server order" do
      second = Map.put(tld_data(), "tld", "org")

      pages = %{
        1 =>
          {[tld_data()],
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
              {[%ReqDnsimple.Tld{tld: "com.au"}, %ReqDnsimple.Tld{tld: "org"}],
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
               ReqDnsimple.Tld.list_all(
                 tld_page_client(pages, headers),
                 sort: [tld: :desc],
                 per_page: 1
               )

      assert metadata.parse_errors == %{}
      assert Enum.all?(metadata.pages, &(&1.parse_errors == %{}))

      assert_request(
        :get,
        "/v2/tlds",
        %{"sort" => "tld:desc", "page" => 1, "per_page" => 1}
      )

      assert_request(
        :get,
        "/v2/tlds",
        %{"sort" => "tld:desc", "page" => 2, "per_page" => 1}
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{})

      assert {:error, %ReqDnsimple.Error{reason: {:invalid_option, :page}, metadata: nil}} =
               ReqDnsimple.Tld.list_all(request, page: 2)

      for opts <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Tld.list_all(request, opts)
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
        tld_response_client(fn
          1 -> {200, %{"data" => [tld_data()], "pagination" => first_page}}
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
               ReqDnsimple.Tld.list_all(http_client)

      assert_request(:get, "/v2/tlds", %{"page" => 1})
      assert_request(:get, "/v2/tlds", %{"page" => 2})

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
               ReqDnsimple.Tld.list_all(
                 tld_response_client(fn
                   1 -> {200, %{"data" => [tld_data()], "pagination" => first_page}}
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
               ReqDnsimple.Tld.list_all(
                 tld_response_client(fn _page ->
                   {200, %{"data" => [tld_data()], "pagination" => repeated}}
                 end)
               )
    end
  end

  describe "list_extended_attributes/2" do
    test "getTldExtendedAttributes retrieves typed definitions without pagination or a body" do
      body = extended_attributes_body()

      assert {:ok,
              {[
                 %ReqDnsimple.Tld.ExtendedAttribute{
                   name: "uk_legal_type",
                   description: "Legal type of the registrant",
                   required: true,
                   title: "Legal type",
                   options: [
                     %ReqDnsimple.Tld.ExtendedAttribute.Option{
                       title: "Individual",
                       value: "IND",
                       description: "A private individual"
                     }
                   ]
                 },
                 %ReqDnsimple.Tld.ExtendedAttribute{
                   name: "x-registry-free-text",
                   description: "",
                   required: false,
                   title: nil,
                   options: []
                 }
               ], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Tld.list_extended_attributes(client(200, body), "co.uk")

      assert_request(:get, "/v2/tlds/co.uk/extended_attributes", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTldExtendedAttributes accepts an empty suffix and rejects invalid types before HTTP" do
      assert {:ok, {[], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Tld.list_extended_attributes(
                 client(200, %{"data" => []}),
                 ""
               )

      assert_request(:get, "/v2/tlds//extended_attributes", %{}, nil)

      request = client(200, %{"data" => []})

      for tld <- [nil, 1, 1.5, [], %{}] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Tld.list_extended_attributes(request, tld)
      end

      refute_received {:request, _request}
    end

    test "getTldExtendedAttributes preserves an explicitly empty title" do
      body = put_in(extended_attributes_body(), ["data", Access.at(0), "title"], "")

      assert {:ok,
              {[%ReqDnsimple.Tld.ExtendedAttribute{title: ""}, _free_text],
               %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Tld.list_extended_attributes(client(200, body), "co.uk")

      assert_request(:get, "/v2/tlds/co.uk/extended_attributes", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTldExtendedAttributes rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(extended_attributes_body(), ["data", Access.at(0), "required"], 1),
        put_in(extended_attributes_body(), ["data", Access.at(0), "options"], nil),
        put_in(
          extended_attributes_body(),
          ["data", Access.at(0), "options", Access.at(0), "value"],
          1
        )
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Tld.list_extended_attributes(client(200, body), "com")

        assert_request(:get, "/v2/tlds/com/extended_attributes", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTldExtendedAttributes rejects an explicit null title without partial success" do
      body =
        update_in(extended_attributes_body(), ["data"], fn attributes ->
          attributes ++
            [
              %{
                "name" => "x-registry-null-title",
                "description" => "Malformed later attribute",
                "required" => false,
                "title" => nil,
                "options" => []
              }
            ]
        end)

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 200, response: ^body},
                metadata: %ReqDnsimple.Metadata{status: 200}
              }} =
               ReqDnsimple.Tld.list_extended_attributes(client(200, body), "co.uk")

      assert_request(:get, "/v2/tlds/co.uk/extended_attributes", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTldExtendedAttributes preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"tld" => ["was not found"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Tld.list_extended_attributes(client(status, body), "com")

        assert_request(:get, "/v2/tlds/com/extended_attributes", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTldExtendedAttributes preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Tld.list_extended_attributes(
                 transport_error_client(:timeout),
                 "com"
               )
    end
  end

  defp tld_body do
    %{"data" => tld_data()}
  end

  defp tld_data do
    %{
      "tld" => "com.au",
      "tld_type" => 1,
      "whois_privacy" => true,
      "auto_renew_only" => false,
      "idn" => true,
      "minimum_registration" => 0,
      "registration_enabled" => true,
      "renewal_enabled" => true,
      "transfer_enabled" => true,
      "dnssec_interface_type" => "ds",
      "name_server_min" => 2,
      "name_server_max" => 13,
      "trustee_service_enabled" => false,
      "trustee_service_required" => false
    }
  end

  defp tld_page_client(pages, headers) do
    tld_response_client(fn page ->
      {data, pagination} = Map.fetch!(pages, page)
      {200, %{"data" => data, "pagination" => pagination}, Map.get(headers, page, [])}
    end)
  end

  defp tld_response_client(response_for_page) do
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

  defp extended_attributes_body do
    %{
      "data" => [
        %{
          "name" => "uk_legal_type",
          "description" => "Legal type of the registrant",
          "required" => true,
          "title" => "Legal type",
          "options" => [
            %{
              "title" => "Individual",
              "value" => "IND",
              "description" => "A private individual"
            }
          ]
        },
        %{
          "name" => "x-registry-free-text",
          "description" => "",
          "required" => false,
          "options" => []
        }
      ]
    }
  end
end
