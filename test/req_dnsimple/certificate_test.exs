defmodule ReqDnsimple.CertificateTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @server_pem """
  -----BEGIN CERTIFICATE-----
  FAKE-OFFLINE-SERVER-NOT-A-CERTIFICATE
  -----END CERTIFICATE-----
  """
  @chain_pem """
  -----BEGIN CERTIFICATE-----
  FAKE-OFFLINE-INTERMEDIATE
  -----END CERTIFICATE-----
  """
  @private_key_pem """
  -----BEGIN PRIVATE KEY-----
  FAKE-OFFLINE-NOT-A-PRIVATE-KEY
  -----END PRIVATE KEY-----
  """
  @download_data %{
    "server" => @server_pem,
    "root" => nil,
    "chain" => [@chain_pem]
  }
  @certificate_data %{
    "id" => 202,
    "domain_id" => 100,
    "name" => "api",
    "common_name" => "api.example.test",
    "years" => 1,
    "csr" => nil,
    "state" => "requesting",
    "auto_renew" => false,
    "alternate_names" => [],
    "authority_identifier" => "letsencrypt",
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:00:00+02:00",
    "expires_at" => nil,
    "expires_on" => nil,
    "contact_id" => nil
  }
  @pagination %{
    "current_page" => 1,
    "per_page" => 1,
    "total_entries" => 1,
    "total_pages" => 1
  }
  @purchase_data %{
    "id" => 101,
    "certificate_id" => 202,
    "state" => "new",
    "auto_renew" => false,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:01:00+02:00"
  }
  @renewal_data %{
    "id" => 505,
    "old_certificate_id" => 202,
    "new_certificate_id" => 404,
    "state" => "cancelled",
    "auto_renew" => false,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:01:00+02:00"
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
    test "every certificate operation, alias and scoped overload preserves HTTP metadata" do
      contracts = [
        {:list_page, [1010, "example.test", []], 200,
         %{"data" => [@certificate_data], "pagination" => @pagination}},
        {:list, [1010, "example.test", []], 200,
         %{"data" => [@certificate_data], "pagination" => @pagination}},
        {:get, [1010, "example.test", 202], 200, %{"data" => @certificate_data}},
        {:download, [1010, "example.test", 202], 200, %{"data" => @download_data}},
        {:get_private_key, [1010, "example.test", 202], 200,
         %{"data" => %{"private_key" => @private_key_pem}}},
        {:purchase_letsencrypt, [1010, "example.test", []], 201, %{"data" => @purchase_data}},
        {:purchase_letsencrypt_renewal, [1010, "example.test", 202, []], 201,
         %{"data" => @renewal_data}},
        {:issue_letsencrypt, [1010, "example.test", 202], 202, %{"data" => @certificate_data}},
        {:issue_letsencrypt_renewal, [1010, "example.test", 202, 505], 202,
         %{"data" => @certificate_data}}
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
            pagination: Map.get(response_body, "pagination")
        }

        if http_status == 404 do
          assert {:error,
                  %ReqDnsimple.Error{
                    reason: %{status: 404, response: ^response_body},
                    metadata: ^expected_metadata
                  }} = apply(ReqDnsimple.Certificate, operation, [req | call_args])
        else
          assert {:ok, {_data, %ReqDnsimple.Metadata{} = metadata}} =
                   apply(ReqDnsimple.Certificate, operation, [req | call_args])

          assert metadata == expected_metadata
        end

        assert_receive {:request, %Req.Request{}}
        refute_received {:request, _request}
      end
    end

    test "malformed headers do not discard valid certificate data" do
      assert {:ok,
              {%ReqDnsimple.Certificate{id: 202},
               %ReqDnsimple.Metadata{
                 status: 200,
                 rate_limit_reset: nil,
                 rate_limit_remaining: 7,
                 parse_errors: %{rate_limit_reset: {:invalid_header, ["invalid"]}}
               }}} =
               ReqDnsimple.Certificate.get(
                 client(200, %{"data" => @certificate_data}, self(),
                   "x-ratelimit-reset": "invalid",
                   "x-ratelimit-remaining": "7"
                 ),
                 1010,
                 "example.test",
                 202
               )

      assert_request(:get, "/v2/1010/domains/example.test/certificates/202")
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
        body = Map.merge(%{"data" => [@certificate_data]}, extra)

        assert {:ok,
                {[%ReqDnsimple.Certificate{id: 202}],
                 %ReqDnsimple.Metadata{
                   status: 200,
                   pagination: ^pagination,
                   pages: [],
                   parse_errors: ^parse_errors
                 }}} =
                 apply(ReqDnsimple.Certificate, operation, [
                   client(200, body),
                   1010,
                   "example.test",
                   []
                 ])

        assert_request(:get, "/v2/1010/domains/example.test/certificates")
        refute_received {:request, _request}
      end
    end

    test "list_all retains ordered page metadata and latest response budgets for both scopes" do
      first_page = %{@pagination | "total_entries" => 2, "total_pages" => 2}
      second_page = %{first_page | "current_page" => 2}

      for scoped? <- [false, true] do
        req =
          certificate_response_client(fn page ->
            pagination = if page == 1, do: first_page, else: second_page

            {200,
             %{
               "data" => [Map.put(@certificate_data, "id", 201 + page)],
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
            |> ReqDnsimple.Certificate.list_all("example.test", per_page: 1)
          else
            ReqDnsimple.Certificate.list_all(req, 1010, "example.test", per_page: 1)
          end

        assert {:ok,
                {[%ReqDnsimple.Certificate{id: 202}, %ReqDnsimple.Certificate{id: 203}],
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
            "/v2/1010/domains/example.test/certificates",
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
        certificate_response_client(fn
          1 ->
            {200, %{"data" => [@certificate_data], "pagination" => first_page}, @response_headers}

          2 ->
            {:error, :timeout}
        end)

      assert {:error,
              %ReqDnsimple.Error{
                reason: %Req.TransportError{reason: :timeout},
                metadata: ^expected_metadata
              }} = ReqDnsimple.Certificate.list_all(req, 1010, "example.test")

      assert_request(:get, "/v2/1010/domains/example.test/certificates", %{"page" => 1})
      assert_request(:get, "/v2/1010/domains/example.test/certificates", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "list_page/4 and list/4" do
    test "listCertificates merges inherited keyword params without crashing" do
      req =
        client(200, %{"data" => [@certificate_data], "pagination" => @pagination})
        |> Req.merge(params: [common_name_like: "www"])

      assert {:ok,
              {[%ReqDnsimple.Certificate{id: 202}],
               %ReqDnsimple.Metadata{pagination: @pagination}}} =
               ReqDnsimple.Certificate.list_page(req, 1010, "dnsimple.us", [])

      assert_request(
        :get,
        "/v2/1010/domains/dnsimple.us/certificates",
        %{"common_name_like" => "www"}
      )

      refute_received {:request, _request}
    end

    test "listCertificates operation options override inherited encoded query keys" do
      req =
        client(200, %{"data" => [@certificate_data], "pagination" => @pagination})
        |> Req.merge(params: [{"page", 9}, {:page, 8}, {"sort", "id:desc"}, {"trace", "offline"}])

      assert {:ok,
              {[%ReqDnsimple.Certificate{id: 202}],
               %ReqDnsimple.Metadata{pagination: @pagination}}} =
               ReqDnsimple.Certificate.list_page(req, 1010, "dnsimple.us",
                 page: 1,
                 per_page: 1,
                 sort: [expiration: :asc]
               )

      assert_request(
        :get,
        "/v2/1010/domains/dnsimple.us/certificates",
        %{"page" => 1, "per_page" => 1, "sort" => "expiration:asc", "trace" => "offline"}
      )

      refute_received {:request, _request}
    end

    test "listCertificates sends ordered options once and decodes pending and issued certificates" do
      issued =
        Map.merge(@certificate_data, %{
          "id" => 203,
          "csr" => "FAKE-OFFLINE-CSR",
          "state" => "issued",
          "alternate_names" => ["docs.example.test"],
          "expires_at" => "2027-09-01T10:00:00+02:00",
          "expires_on" => "2027-09-01"
        })

      pagination = %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}

      assert {:ok,
              {[
                 %ReqDnsimple.Certificate{
                   id: 202,
                   csr: nil,
                   state: "requesting",
                   auto_renew: false,
                   alternate_names: [],
                   expires_at: nil,
                   expires_on: nil,
                   contact_id: nil
                 },
                 %ReqDnsimple.Certificate{
                   id: 203,
                   csr: "FAKE-OFFLINE-CSR",
                   state: "issued",
                   alternate_names: ["docs.example.test"],
                   expires_at: ~U[2027-09-01 08:00:00Z],
                   expires_on: ~D[2027-09-01]
                 }
               ], %ReqDnsimple.Metadata{pagination: ^pagination}}} =
               ReqDnsimple.Certificate.list_page(
                 client(200, %{
                   "data" => [@certificate_data, issued],
                   "pagination" => pagination
                 }),
                 1010,
                 "example.test",
                 sort: [id: :asc, common_name: :desc, expiration: :asc],
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/certificates",
        %{
          "sort" => "id:asc,common_name:desc,expiration:asc",
          "page" => 2,
          "per_page" => 1
        },
        nil
      )

      refute_received {:request, _request}
    end

    test "listCertificates alias requests one empty page without materializing defaults" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 0,
        "total_pages" => 0
      }

      assert {:ok, {[], %ReqDnsimple.Metadata{pagination: ^pagination}}} =
               ReqDnsimple.Certificate.list(
                 client(200, %{"data" => [], "pagination" => pagination}),
                 0,
                 0
               )

      assert_request(:get, "/v2/0/domains/0/certificates", %{}, nil)
      refute_received {:request, _request}
    end

    test "listCertificates accepts omitted and null optional contact IDs" do
      for data <- [
            Map.delete(@certificate_data, "contact_id"),
            Map.put(@certificate_data, "contact_id", nil)
          ] do
        assert {:ok,
                {[%ReqDnsimple.Certificate{contact_id: nil}],
                 %ReqDnsimple.Metadata{pagination: @pagination}}} =
                 ReqDnsimple.Certificate.list_page(
                   client(200, %{"data" => [data], "pagination" => @pagination}),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates")
        refute_received {:request, _request}
      end
    end

    test "listCertificates rejects invalid paths and options before HTTP" do
      request =
        client(200, %{"data" => [@certificate_data], "pagination" => @pagination})

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
        {1010, "example.test", [sort: [name: :asc]]},
        {1010, "example.test", [sort: [expiration: :sideways]]},
        {1010, "example.test", [page: 0]},
        {1010, "example.test", [per_page: 0]},
        {1010, "example.test", [per_page: 101]}
      ]

      for {account_id, domain, opts} <- invalid_calls do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.list_page(request, account_id, domain, opts)
      end

      refute_received {:request, _request}
    end

    test "listCertificates preserves HTTP and transport failures" do
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
                 ReqDnsimple.Certificate.list_page(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Certificate.list_page(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end

    test "listCertificates rejects malformed successful responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => @pagination},
        %{"data" => %{}, "pagination" => @pagination},
        %{"data" => [Map.delete(@certificate_data, "csr")], "pagination" => @pagination},
        %{
          "data" => [Map.delete(@certificate_data, "expires_at")],
          "pagination" => @pagination
        },
        %{
          "data" => [Map.put(@certificate_data, "common_name", nil)],
          "pagination" => @pagination
        },
        %{
          "data" => [Map.put(@certificate_data, "state", "unknown")],
          "pagination" => @pagination
        }
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Certificate.list_page(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  describe "list_all/4" do
    test "enumerates from page one while preserving options and server order" do
      second = Map.put(@certificate_data, "id", 203)

      pages = %{
        1 =>
          {[@certificate_data],
           %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}},
        2 =>
          {[second],
           %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}}
      }

      assert {:ok,
              {[
                 %ReqDnsimple.Certificate{id: 202},
                 %ReqDnsimple.Certificate{id: 203}
               ], %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.list_all(
                 certificate_page_client(pages),
                 1010,
                 "example.test",
                 sort: [expiration: :desc, id: :asc],
                 per_page: 1
               )

      query = %{"sort" => "expiration:desc,id:asc", "per_page" => 1}

      assert_request(
        :get,
        "/v2/1010/domains/example.test/certificates",
        Map.put(query, "page", 1)
      )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/certificates",
        Map.put(query, "page", 2)
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      assert {:error, %ReqDnsimple.Error{reason: {:invalid_option, :page}, metadata: nil}} =
               ReqDnsimple.Certificate.list_all(
                 request,
                 1010,
                 "example.test",
                 page: 2
               )

      for opts <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.list_all(
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
        certificate_response_client(fn
          1 -> {200, %{"data" => [@certificate_data], "pagination" => first_page}}
          2 -> {503, %{"message" => "unavailable"}}
        end)

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
               ReqDnsimple.Certificate.list_all(http_client, 1010, "example.test")

      assert_request(:get, "/v2/1010/domains/example.test/certificates", %{"page" => 1})
      assert_request(:get, "/v2/1010/domains/example.test/certificates", %{"page" => 2})

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
               ReqDnsimple.Certificate.list_all(
                 certificate_response_client(fn _page ->
                   {200, %{"data" => [@certificate_data], "pagination" => repeated}}
                 end),
                 1010,
                 "example.test"
               )

      assert_request(:get, "/v2/1010/domains/example.test/certificates", %{"page" => 1})
      assert_request(:get, "/v2/1010/domains/example.test/certificates", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "issue_letsencrypt/4" do
    test "issueLetsencryptCertificate sends one bodyless request with the certificate ID" do
      purchase_id = @purchase_data["id"]
      certificate_id = @purchase_data["certificate_id"]
      refute purchase_id == certificate_id

      assert {:ok,
              {%ReqDnsimple.Certificate{
                 id: 202,
                 domain_id: 100,
                 name: "api",
                 common_name: "api.example.test",
                 years: 1,
                 csr: nil,
                 state: "requesting",
                 auto_renew: false,
                 alternate_names: [],
                 authority_identifier: "letsencrypt",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:00:00Z],
                 expires_at: nil,
                 expires_on: nil,
                 contact_id: nil
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.issue_letsencrypt(
                 client(202, %{"data" => @certificate_data}),
                 1010,
                 "example.test",
                 certificate_id
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/certificates/letsencrypt/202/issue",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "issueLetsencryptCertificate accepts integer paths and preserves zero identifiers" do
      assert {:ok, {%ReqDnsimple.Certificate{id: 202}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.issue_letsencrypt(
                 client(202, %{"data" => @certificate_data}),
                 0,
                 0,
                 0
               )

      assert_request(:post, "/v2/0/domains/0/certificates/letsencrypt/0/issue", %{}, nil)
      refute_received {:request, _request}
    end

    test "issueLetsencryptCertificate rejects invalid path parameters before HTTP" do
      request = client(202, %{"data" => @certificate_data})

      for {account_id, domain, certificate_id} <- [
            {"1010", "example.test", 202},
            {nil, "example.test", 202},
            {1010, nil, 202},
            {1010, :example, 202},
            {1010, "example.test", "202"},
            {1010, "example.test", nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.issue_letsencrypt(
                   request,
                   account_id,
                   domain,
                   certificate_id
                 )
      end

      refute_received {:request, _request}
    end

    test "issueLetsencryptCertificate preserves documented and shared HTTP failures" do
      for status <- [400, 404, 412, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"certificate" => ["cannot be issued"]}
        }

        request = client(status, body) |> Req.merge(retry: :transient)

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Certificate.issue_letsencrypt(
                   request,
                   1010,
                   "example.test",
                   202
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/issue",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "issueLetsencryptCertificate returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@certificate_data, "id")},
        %{"data" => Map.delete(@certificate_data, "csr")},
        %{"data" => Map.delete(@certificate_data, "expires_at")},
        %{"data" => Map.put(@certificate_data, "common_name", nil)},
        %{"data" => Map.put(@certificate_data, "state", "unknown")},
        %{"data" => Map.put(@certificate_data, "auto_renew", 0)},
        %{"data" => Map.put(@certificate_data, "alternate_names", [nil])},
        %{"data" => Map.put(@certificate_data, "created_at", "not-a-date")}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 202, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 202}
                }} =
                 ReqDnsimple.Certificate.issue_letsencrypt(
                   client(202, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/issue"
        )

        refute_received {:request, _request}
      end
    end

    test "issueLetsencryptCertificate preserves an omitted optional contact ID" do
      body = %{"data" => Map.delete(@certificate_data, "contact_id")}

      assert {:ok, {%ReqDnsimple.Certificate{contact_id: nil}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.issue_letsencrypt(
                 client(202, body),
                 1010,
                 "example.test",
                 202
               )

      assert_request(:post, "/v2/1010/domains/example.test/certificates/letsencrypt/202/issue")
      refute_received {:request, _request}
    end

    test "issueLetsencryptCertificate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Certificate.issue_letsencrypt(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202
               )
    end
  end

  describe "issue_letsencrypt_renewal/5" do
    test "issueRenewalLetsencryptCertificate sends one bodyless request with both IDs" do
      original_certificate_id = @renewal_data["old_certificate_id"]
      renewal_id = @renewal_data["id"]
      new_certificate_id = @renewal_data["new_certificate_id"]

      refute original_certificate_id == renewal_id
      refute renewal_id == new_certificate_id

      response_data = Map.put(@certificate_data, "id", new_certificate_id)

      assert {:ok,
              {%ReqDnsimple.Certificate{
                 id: 404,
                 domain_id: 100,
                 name: "api",
                 common_name: "api.example.test",
                 years: 1,
                 csr: nil,
                 state: "requesting",
                 auto_renew: false,
                 alternate_names: [],
                 authority_identifier: "letsencrypt",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:00:00Z],
                 expires_at: nil,
                 expires_on: nil,
                 contact_id: nil
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.issue_letsencrypt_renewal(
                 client(202, %{"data" => response_data}),
                 1010,
                 "example.test",
                 original_certificate_id,
                 renewal_id
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals/505/issue",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "issueRenewalLetsencryptCertificate accepts integer paths and zero identifiers" do
      assert {:ok, {%ReqDnsimple.Certificate{id: 202}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.issue_letsencrypt_renewal(
                 client(202, %{"data" => @certificate_data}),
                 0,
                 0,
                 0,
                 0
               )

      assert_request(
        :post,
        "/v2/0/domains/0/certificates/letsencrypt/0/renewals/0/issue",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "issueRenewalLetsencryptCertificate rejects invalid path parameters before HTTP" do
      request = client(202, %{"data" => @certificate_data})

      for {account_id, domain, certificate_id, renewal_id} <- [
            {"1010", "example.test", 202, 505},
            {nil, "example.test", 202, 505},
            {1010, nil, 202, 505},
            {1010, :example, 202, 505},
            {1010, "example.test", "202", 505},
            {1010, "example.test", nil, 505},
            {1010, "example.test", 202, "505"},
            {1010, "example.test", 202, nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.issue_letsencrypt_renewal(
                   request,
                   account_id,
                   domain,
                   certificate_id,
                   renewal_id
                 )
      end

      refute_received {:request, _request}
    end

    test "issueRenewalLetsencryptCertificate preserves HTTP failures" do
      for status <- [400, 404, 412, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"renewal" => ["cannot be issued"]}
        }

        request = client(status, body) |> Req.merge(retry: :transient)

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Certificate.issue_letsencrypt_renewal(
                   request,
                   1010,
                   "example.test",
                   202,
                   505
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals/505/issue",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "issueRenewalLetsencryptCertificate returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@certificate_data, "id")},
        %{"data" => Map.delete(@certificate_data, "csr")},
        %{"data" => Map.delete(@certificate_data, "expires_at")},
        %{"data" => Map.put(@certificate_data, "csr", :invalid)},
        %{"data" => Map.put(@certificate_data, "state", "unknown")},
        %{"data" => Map.put(@certificate_data, "alternate_names", [nil])},
        %{"data" => Map.put(@certificate_data, "updated_at", "not-a-date")}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 202, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 202}
                }} =
                 ReqDnsimple.Certificate.issue_letsencrypt_renewal(
                   client(202, body),
                   1010,
                   "example.test",
                   202,
                   505
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals/505/issue"
        )

        refute_received {:request, _request}
      end
    end

    test "issueRenewalLetsencryptCertificate preserves optional field omission and null" do
      for data <- [
            Map.delete(@certificate_data, "contact_id"),
            Map.put(@certificate_data, "contact_id", nil)
          ] do
        assert {:ok,
                {%ReqDnsimple.Certificate{contact_id: nil, csr: nil, expires_at: nil},
                 %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Certificate.issue_letsencrypt_renewal(
                   client(202, %{"data" => data}),
                   1010,
                   "example.test",
                   202,
                   505
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals/505/issue"
        )

        refute_received {:request, _request}
      end
    end

    test "issueRenewalLetsencryptCertificate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Certificate.issue_letsencrypt_renewal(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202,
                 505
               )
    end
  end

  describe "get/4" do
    test "getCertificate sends one bodyless request and decodes a pending certificate" do
      assert {:ok,
              {%ReqDnsimple.Certificate{
                 id: 202,
                 domain_id: 100,
                 name: "api",
                 common_name: "api.example.test",
                 years: 1,
                 csr: nil,
                 state: "requesting",
                 auto_renew: false,
                 alternate_names: [],
                 authority_identifier: "letsencrypt",
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:00:00Z],
                 expires_at: nil,
                 expires_on: nil,
                 contact_id: nil
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.get(
                 client(200, %{"data" => @certificate_data}),
                 1010,
                 "example.test",
                 202
               )

      assert_request(:get, "/v2/1010/domains/example.test/certificates/202", %{}, nil)
      refute_received {:request, _request}
    end

    test "getCertificate accepts integer paths and decodes issued certificate expiry" do
      csr = """
      -----BEGIN CERTIFICATE REQUEST-----
      FAKE-OFFLINE-NOT-A-CSR
      -----END CERTIFICATE REQUEST-----
      """

      data = %{
        @certificate_data
        | "csr" => csr,
          "state" => "issued",
          "alternate_names" => ["docs.example.test"],
          "expires_at" => "2027-09-01T10:00:00+02:00",
          "expires_on" => "2027-09-01"
      }

      assert {:ok,
              {%ReqDnsimple.Certificate{
                 csr: ^csr,
                 state: "issued",
                 alternate_names: ["docs.example.test"],
                 expires_at: ~U[2027-09-01 08:00:00Z],
                 expires_on: ~D[2027-09-01]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.get(client(200, %{"data" => data}), 0, 0, 0)

      assert_request(:get, "/v2/0/domains/0/certificates/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "getCertificate rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @certificate_data})

      for {account_id, domain, certificate_id} <- [
            {"1010", "example.test", 202},
            {nil, "example.test", 202},
            {1010, nil, 202},
            {1010, :example, 202},
            {1010, "example.test", "202"},
            {1010, "example.test", nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.get(request, account_id, domain, certificate_id)
      end

      refute_received {:request, _request}
    end

    test "getCertificate preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"certificate" => ["was not found"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Certificate.get(
                   client(status, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202")
        refute_received {:request, _request}
      end
    end

    test "getCertificate returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@certificate_data, "id")},
        %{"data" => Map.put(@certificate_data, "auto_renew", 0)},
        %{"data" => Map.put(@certificate_data, "alternate_names", [nil])},
        %{"data" => Map.put(@certificate_data, "state", "unknown")},
        %{"data" => Map.put(@certificate_data, "contact_id", "202")},
        %{"data" => Map.put(@certificate_data, "created_at", "not-a-date")},
        %{"data" => Map.put(@certificate_data, "expires_on", "not-a-date")}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Certificate.get(
                   client(200, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202")
        refute_received {:request, _request}
      end
    end

    test "getCertificate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Certificate.get(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202
               )
    end
  end

  describe "download/4" do
    test "downloadCertificate sends one bodyless request and preserves the typed PEM bundle" do
      assert {:ok,
              {%ReqDnsimple.Certificate.Download{
                 server: @server_pem,
                 root: nil,
                 chain: [@chain_pem]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.download(
                 client(200, %{"data" => @download_data}),
                 1010,
                 "example.test",
                 202
               )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/certificates/202/download",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "downloadCertificate accepts an integer domain and preserves zero identifiers" do
      root_pem = """
      -----BEGIN CERTIFICATE-----
      FAKE-OFFLINE-ROOT
      -----END CERTIFICATE-----
      """

      data = %{@download_data | "root" => root_pem, "chain" => []}

      assert {:ok,
              {%ReqDnsimple.Certificate.Download{root: ^root_pem, chain: []},
               %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.download(
                 client(200, %{"data" => data}),
                 0,
                 0,
                 0
               )

      assert_request(:get, "/v2/0/domains/0/certificates/0/download", %{}, nil)
    end

    test "downloadCertificate rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @download_data})

      for {account_id, domain, certificate_id} <- [
            {"1010", "example.test", 202},
            {nil, "example.test", 202},
            {1010, nil, 202},
            {1010, :example, 202},
            {1010, "example.test", "202"},
            {1010, "example.test", nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.download(request, account_id, domain, certificate_id)
      end

      refute_received {:request, _request}
    end

    test "downloadCertificate preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 428, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"certificate" => ["is not downloadable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Certificate.download(
                   client(status, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202/download")
        refute_received {:request, _request}
      end
    end

    test "downloadCertificate returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@download_data, "server")},
        %{"data" => Map.put(@download_data, "server", nil)},
        %{"data" => Map.put(@download_data, "root", 0)},
        %{"data" => Map.put(@download_data, "chain", nil)},
        %{"data" => Map.put(@download_data, "chain", [nil])}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Certificate.download(
                   client(200, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202/download")
        refute_received {:request, _request}
      end
    end

    test "downloadCertificate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Certificate.download(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202
               )
    end
  end

  describe "get_private_key/4" do
    test "getCertificatePrivateKey sends one bodyless request and preserves the PEM text" do
      assert {:ok,
              {%ReqDnsimple.Certificate.PrivateKey{private_key: @private_key_pem},
               %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.get_private_key(
                 client(200, %{"data" => %{"private_key" => @private_key_pem}}),
                 1010,
                 "example.test",
                 202
               )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/certificates/202/private_key",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "getCertificatePrivateKey accepts an integer domain and preserves zero identifiers" do
      assert {:ok,
              {%ReqDnsimple.Certificate.PrivateKey{private_key: @private_key_pem},
               %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.get_private_key(
                 client(200, %{"data" => %{"private_key" => @private_key_pem}}),
                 0,
                 0,
                 0
               )

      assert_request(:get, "/v2/0/domains/0/certificates/0/private_key", %{}, nil)
    end

    test "getCertificatePrivateKey rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => %{"private_key" => @private_key_pem}})

      for {account_id, domain, certificate_id} <- [
            {"1010", "example.test", 202},
            {nil, "example.test", 202},
            {1010, nil, 202},
            {1010, :example, 202},
            {1010, "example.test", "202"},
            {1010, "example.test", nil}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.get_private_key(
                   request,
                   account_id,
                   domain,
                   certificate_id
                 )
      end

      refute_received {:request, _request}
    end

    test "getCertificatePrivateKey preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 428, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"certificate" => ["private key is not present"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Certificate.get_private_key(
                   client(status, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202/private_key")
        refute_received {:request, _request}
      end
    end

    test "getCertificatePrivateKey returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        %{"data" => %{"private_key" => nil}},
        %{"data" => %{"private_key" => 0}}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Certificate.get_private_key(
                   client(200, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202/private_key")
        refute_received {:request, _request}
      end
    end

    test "getCertificatePrivateKey preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Certificate.get_private_key(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202
               )
    end
  end

  describe "purchase_letsencrypt/3 and purchase_letsencrypt/4" do
    test "purchaseLetsencryptCertificate sends all attributes once and returns typed data" do
      attrs = [
        auto_renew: false,
        name: "api",
        alternate_names: ["docs.example.test", "status.example.test"],
        signature_algorithm: "RSA"
      ]

      assert {:ok,
              {%ReqDnsimple.Certificate.Purchase{
                 id: 101,
                 certificate_id: 202,
                 state: "new",
                 auto_renew: false,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:01:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.purchase_letsencrypt(
                 client(201, %{"data" => @purchase_data}),
                 1010,
                 "example.test",
                 attrs
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/certificates/letsencrypt",
        %{},
        Map.new(attrs)
      )

      refute_received {:request, _request}
    end

    test "purchaseLetsencryptCertificate leaves server defaults omitted" do
      assert {:ok,
              {%ReqDnsimple.Certificate.Purchase{certificate_id: 202}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.purchase_letsencrypt(
                 client(201, %{"data" => @purchase_data}),
                 0,
                 42
               )

      assert_request(:post, "/v2/0/domains/42/certificates/letsencrypt")
      refute_received {:request, _request}
    end

    test "purchaseLetsencryptCertificate preserves apex, wildcard, empty, and false values" do
      for {name, alternate_names} <- [{"", []}, {"*", []}] do
        attrs = [name: name, alternate_names: alternate_names, auto_renew: false]

        assert {:ok,
                {%ReqDnsimple.Certificate.Purchase{auto_renew: false}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   client(201, %{"data" => @purchase_data}),
                   1010,
                   "",
                   attrs
                 )

        assert_request(
          :post,
          "/v2/1010/domains//certificates/letsencrypt",
          %{},
          Map.new(attrs)
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseLetsencryptCertificate accepts every documented purchase state" do
      for state <-
            ~w(new purchased configured submitted issued rejected refunded cancelled requesting failed) do
        body = %{"data" => Map.put(@purchase_data, "state", state)}

        assert {:ok, {%ReqDnsimple.Certificate.Purchase{state: ^state}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   client(201, body),
                   1010,
                   "example.test"
                 )

        assert_request(:post, "/v2/1010/domains/example.test/certificates/letsencrypt")
        refute_received {:request, _request}
      end
    end

    test "purchaseLetsencryptCertificate rejects invalid inputs before HTTP" do
      request = client(201, %{"data" => @purchase_data})

      invalid_calls = [
        {"1010", "example.test", []},
        {nil, "example.test", []},
        {1010, nil, []},
        {1010, 1.5, []},
        {1010, "example.test", [auto_renew: nil]},
        {1010, "example.test", [auto_renew: 0]},
        {1010, "example.test", [name: nil]},
        {1010, "example.test", [name: 0]},
        {1010, "example.test", [alternate_names: nil]},
        {1010, "example.test", [alternate_names: ["valid", 0]]},
        {1010, "example.test", [signature_algorithm: nil]},
        {1010, "example.test", [signature_algorithm: "DSA"]},
        {1010, "example.test", [unknown: true]},
        {1010, "example.test", %{}}
      ]

      for {account_id, domain, attrs} <- invalid_calls do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   request,
                   account_id,
                   domain,
                   attrs
                 )
      end

      refute_received {:request, _request}
    end

    test "purchaseLetsencryptCertificate rejects malformed keyword containers before HTTP" do
      request = client(201, %{"data" => @purchase_data})

      for attrs <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   request,
                   1010,
                   "example.test",
                   attrs
                 )

        refute_received {:request, _request}
      end

      assert {:ok, {%ReqDnsimple.Certificate.Purchase{}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.purchase_letsencrypt(
                 request,
                 1010,
                 "example.test",
                 name: "api"
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/certificates/letsencrypt",
        %{},
        %{name: "api"}
      )

      refute_received {:request, _request}
    end

    test "purchaseLetsencryptCertificate preserves HTTP failures and disables retries" do
      for status <- [400, 412, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"name" => ["is not available"]}
        }

        request = client(status, body) |> Req.merge(retry: :transient)

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   request,
                   1010,
                   "example.test",
                   name: "api"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt",
          %{},
          %{name: "api"}
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseLetsencryptCertificate returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@purchase_data, "id")},
        %{"data" => Map.put(@purchase_data, "id", "101")},
        %{"data" => Map.put(@purchase_data, "certificate_id", nil)},
        %{"data" => Map.put(@purchase_data, "state", "unknown")},
        %{"data" => Map.put(@purchase_data, "auto_renew", nil)},
        %{"data" => Map.put(@purchase_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(@purchase_data, "updated_at", nil)}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 201, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 201}
                }} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   client(201, body),
                   1010,
                   "example.test"
                 )

        assert_request(:post, "/v2/1010/domains/example.test/certificates/letsencrypt")
        refute_received {:request, _request}
      end
    end

    test "purchaseLetsencryptCertificate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Certificate.purchase_letsencrypt(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "purchase_letsencrypt_renewal/4 and purchase_letsencrypt_renewal/5" do
    test "purchaseRenewalLetsencryptCertificate sends all attributes once and returns typed data" do
      attrs = [auto_renew: false, signature_algorithm: "RSA"]

      assert {:ok,
              {%ReqDnsimple.Certificate.Renewal{
                 id: 505,
                 old_certificate_id: 202,
                 new_certificate_id: 404,
                 state: "cancelled",
                 auto_renew: false,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:01:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                 client(201, %{"data" => @renewal_data}),
                 1010,
                 "example.test",
                 202,
                 attrs
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals",
        %{},
        Map.new(attrs)
      )

      refute_received {:request, _request}
    end

    test "purchaseRenewalLetsencryptCertificate leaves server defaults omitted" do
      assert {:ok, {%ReqDnsimple.Certificate.Renewal{id: 505}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                 client(201, %{"data" => @renewal_data}),
                 0,
                 0,
                 0
               )

      assert_request(
        :post,
        "/v2/0/domains/0/certificates/letsencrypt/0/renewals",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "purchaseRenewalLetsencryptCertificate accepts every documented renewal state" do
      for state <- ~w(cancelled new renewing renewed failed) do
        body = %{"data" => Map.put(@renewal_data, "state", state)}

        assert {:ok, {%ReqDnsimple.Certificate.Renewal{state: ^state}, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   client(201, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals"
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseRenewalLetsencryptCertificate rejects invalid inputs before HTTP" do
      request = client(201, %{"data" => @renewal_data})

      invalid_calls = [
        {"1010", "example.test", 202, []},
        {nil, "example.test", 202, []},
        {1010, nil, 202, []},
        {1010, 1.5, 202, []},
        {1010, "example.test", "202", []},
        {1010, "example.test", nil, []},
        {1010, "example.test", 202, [auto_renew: nil]},
        {1010, "example.test", 202, [auto_renew: 0]},
        {1010, "example.test", 202, [signature_algorithm: nil]},
        {1010, "example.test", 202, [signature_algorithm: "DSA"]},
        {1010, "example.test", 202, [unknown: true]},
        {1010, "example.test", 202, %{}}
      ]

      for {account_id, domain, certificate_id, attrs} <- invalid_calls do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   request,
                   account_id,
                   domain,
                   certificate_id,
                   attrs
                 )
      end

      refute_received {:request, _request}
    end

    test "purchaseRenewalLetsencryptCertificate rejects malformed keyword containers before HTTP" do
      request = client(201, %{"data" => @renewal_data})

      for attrs <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   request,
                   1010,
                   "example.test",
                   202,
                   attrs
                 )

        refute_received {:request, _request}
      end

      assert {:ok, {%ReqDnsimple.Certificate.Renewal{}, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                 request,
                 1010,
                 "example.test",
                 202,
                 auto_renew: false
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals",
        %{},
        %{auto_renew: false}
      )

      refute_received {:request, _request}
    end

    test "purchaseRenewalLetsencryptCertificate preserves omitted response fields as nil" do
      fields = [
        {"id", :id},
        {"old_certificate_id", :old_certificate_id},
        {"new_certificate_id", :new_certificate_id},
        {"state", :state},
        {"auto_renew", :auto_renew},
        {"created_at", :created_at},
        {"updated_at", :updated_at}
      ]

      for {json_field, struct_field} <- fields do
        body = %{"data" => Map.delete(@renewal_data, json_field)}

        assert {:ok, {%ReqDnsimple.Certificate.Renewal{} = renewal, %ReqDnsimple.Metadata{}}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   client(201, body),
                   1010,
                   "example.test",
                   202
                 )

        assert Map.fetch!(Map.from_struct(renewal), struct_field) == nil

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals"
        )

        refute_received {:request, _request}
      end

      assert {:ok, {%ReqDnsimple.Certificate.Renewal{} = renewal, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                 client(201, %{"data" => %{}}),
                 1010,
                 "example.test",
                 202
               )

      assert renewal == %ReqDnsimple.Certificate.Renewal{}
      assert_request(:post, "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals")
      refute_received {:request, _request}
    end

    test "purchaseRenewalLetsencryptCertificate preserves HTTP failures and disables retries" do
      for status <- [400, 404, 412, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"certificate" => ["cannot be renewed"]}
        }

        request = client(status, body) |> Req.merge(retry: :transient)

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   request,
                   1010,
                   "example.test",
                   202,
                   auto_renew: false
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals",
          %{},
          %{auto_renew: false}
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseRenewalLetsencryptCertificate returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.put(@renewal_data, "id", "505")},
        %{"data" => Map.put(@renewal_data, "id", nil)},
        %{"data" => Map.put(@renewal_data, "old_certificate_id", nil)},
        %{"data" => Map.put(@renewal_data, "new_certificate_id", nil)},
        %{"data" => Map.put(@renewal_data, "state", "unknown")},
        %{"data" => Map.put(@renewal_data, "auto_renew", nil)},
        %{"data" => Map.put(@renewal_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(@renewal_data, "updated_at", nil)}
      ]

      for body <- malformed_payloads do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 201, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 201}
                }} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   client(201, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals"
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseRenewalLetsencryptCertificate preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202
               )
    end
  end

  defp certificate_page_client(pages) do
    certificate_response_client(fn page ->
      {data, pagination} = Map.fetch!(pages, page)
      {200, %{"data" => data, "pagination" => pagination}}
    end)
  end

  defp certificate_response_client(response_for_page) do
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

        {status, body, headers} ->
          {request, Req.Response.new(status: status, body: body, headers: headers)}
      end
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
