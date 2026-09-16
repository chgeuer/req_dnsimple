defmodule ReqDnsimple.QueryParamsTest do
  use ExUnit.Case, async: false

  import ReqDnsimple.TestSupport

  alias ReqDnsimple.{Error, Metadata}

  @page_queries [
    {ReqDnsimple.Zone, :list_page, [], "/v2/1010/zones"},
    {ReqDnsimple.ZoneRecord, :list_page, ["example.com"], "/v2/1010/zones/example.com/records"},
    {ReqDnsimple.Contact, :list_page, [], "/v2/1010/contacts"},
    {ReqDnsimple.BillingCharge, :list_page, [], "/v2/1010/billing/charges"},
    {ReqDnsimple.Domain, :list_page, [], "/v2/1010/domains"},
    {ReqDnsimple.Certificate, :list_page, ["example.com"],
     "/v2/1010/domains/example.com/certificates"},
    {ReqDnsimple.RegistrantChange, :list_page, [], "/v2/1010/registrar/registrant_changes"},
    {ReqDnsimple.DomainPush, :list_page, [], "/v2/1010/pushes"},
    {ReqDnsimple.EmailForward, :list_page, ["example.com"],
     "/v2/1010/domains/example.com/email_forwards"},
    {ReqDnsimple.DelegationSignerRecord, :list_page, ["example.com"],
     "/v2/1010/domains/example.com/ds_records"},
    {ReqDnsimple.PrimaryServer, :list_page, [], "/v2/1010/secondary_dns/primaries"},
    {ReqDnsimple.Service, :list_page, [], "/v2/services"},
    {ReqDnsimple.Service, :list_page_applied, ["example.com"],
     "/v2/1010/domains/example.com/services"},
    {ReqDnsimple.Template, :list_page, [], "/v2/1010/templates"},
    {ReqDnsimple.TemplateRecord, :list_page, [268], "/v2/1010/templates/268/records"},
    {ReqDnsimple.Tld, :list_page, [], "/v2/tlds"},
    {ReqDnsimple.DnsAnalytics, :list_page, [], "/v2/1010/dns_analytics"}
  ]

  for shape <- [:keyword, :map, :string_map, :tuple_list] do
    test "page options override inherited #{shape} parameters without dropping other keys" do
      params = params(unquote(shape), page: 99, per_page: 10, trace: "retained")

      for {module, function, arguments, path} <- @page_queries do
        request = request(params)

        assert {:error, %Error{metadata: %Metadata{status: 404, request_id: "query-probe"}}} =
                 apply(module, function, [request | arguments] ++ [[page: 2, per_page: 20]])

        assert_request(:get, path, %{page: 2, per_page: 20, trace: "retained"})
        refute_received {:request, _request}
      end
    end

    test "research and webhook queries merge inherited #{shape} parameters" do
      research =
        request(params(unquote(shape), domain: "old.example", trace: "retained"))

      assert {:error, %Error{metadata: %Metadata{status: 404, request_id: "query-probe"}}} =
               ReqDnsimple.DomainResearch.get_status(research, domain: "example.com")

      assert_request(:get, "/v2/1010/domains/research/status", %{
        domain: "example.com",
        trace: "retained"
      })

      webhook = request(params(unquote(shape), sort: "id:desc", trace: "retained"))

      assert {:error, %Error{metadata: %Metadata{status: 404, request_id: "query-probe"}}} =
               ReqDnsimple.Webhook.list(webhook, sort: [id: :asc])

      assert_request(:get, "/v2/1010/webhooks", %{sort: "id:asc", trace: "retained"})
      refute_received {:request, _request}
    end
  end

  test "empty inherited parameters do not prevent requests" do
    for params <- [[], %{}],
        {module, function, arguments, path} <- @page_queries do
      assert {:error, %Error{metadata: %Metadata{status: 404, request_id: "query-probe"}}} =
               apply(module, function, [request(params) | arguments] ++ [[page: 2]])

      assert_request(:get, path, %{page: 2})
      refute_received {:request, _request}
    end
  end

  test "scoped construction accepts preconfigured query parameters" do
    test_pid = self()

    request =
      ReqDnsimple.new_client("fake-offline-token",
        account_id: 1010,
        params: [per_page: 10],
        retry: false,
        adapter: fn request ->
          send(test_pid, {:request, request})

          {request,
           Req.Response.new(
             status: 404,
             body: %{"message" => "offline response"},
             headers: [{"x-request-id", "query-probe"}]
           )}
        end
      )

    assert {:error, %Error{metadata: %Metadata{status: 404, request_id: "query-probe"}}} =
             ReqDnsimple.BillingCharge.list_page(request)

    assert_request(:get, "/v2/1010/billing/charges", %{per_page: 10})
  end

  test "client parameters merge with Req defaults without resolving dynamic credentials" do
    defaults = Req.default_options()
    on_exit(fn -> Req.default_options(defaults) end)

    Req.default_options(Keyword.put(defaults, :params, %{"page" => 99, "trace" => "retained"}))

    token = fn -> flunk("constructing a client must not resolve credentials") end

    for request <- [
          ReqDnsimple.new_client("fake-offline-token", account_id: 1010, params: [page: 2]),
          ReqDnsimple.new_unscoped_client("fake-offline-token", params: [page: 2]),
          ReqDnsimple.new_client(token, account_id: 1010, params: [page: 2]),
          ReqDnsimple.new_unscoped_client(token, params: [page: 2])
        ] do
      assert request.options[:params] == %{:page => 2, "trace" => "retained"}
    end
  end

  test "complete enumeration overrides an inherited page and retains billing filters" do
    test_pid = self()

    request =
      ReqDnsimple.new_client("fake-offline-token",
        account_id: 1010,
        params: %{"page" => 99, "per_page" => 1, "start_date" => "2026-09-01"},
        retry: false,
        adapter: fn request ->
          send(test_pid, {:request, request})

          page =
            request.url.query |> URI.decode_query() |> Map.fetch!("page") |> String.to_integer()

          body = %{
            "data" => [
              %{
                "reference" => "page-#{page}",
                "state" => "paid",
                "total_amount" => "1.00",
                "balance_amount" => "0.00",
                "invoiced_at" => "2026-09-01T00:00:00Z",
                "items" => []
              }
            ],
            "pagination" => %{
              "current_page" => page,
              "per_page" => 1,
              "total_entries" => 2,
              "total_pages" => 2
            }
          }

          {request,
           Req.Response.new(
             status: 200,
             body: body,
             headers: [
               {"x-request-id", "billing-page-#{page}"},
               {"x-ratelimit-remaining", to_string(100 - page)}
             ]
           )}
        end
      )

    assert {:ok, {charges, %Metadata{} = metadata}} =
             ReqDnsimple.BillingCharge.list_all(request, end_date: "2026-09-15")

    assert Enum.map(charges, & &1.reference) == ["page-1", "page-2"]

    assert metadata == %Metadata{
             rate_limit_remaining: 98,
             pages:
               for page <- 1..2 do
                 %Metadata{
                   status: 200,
                   pagination: %{
                     "current_page" => page,
                     "per_page" => 1,
                     "total_entries" => 2,
                     "total_pages" => 2
                   },
                   request_id: "billing-page-#{page}",
                   rate_limit_remaining: 100 - page
                 }
               end
           }

    for page <- 1..2 do
      assert_request(:get, "/v2/1010/billing/charges", %{
        page: page,
        per_page: 1,
        start_date: "2026-09-01",
        end_date: "2026-09-15"
      })
    end

    refute_received {:request, _request}
  end

  test "the shared merge preserves Req options and replaces every spelling of a query key" do
    original =
      ReqDnsimple.new_client("fake-offline-token",
        account_id: 1010,
        params: [{"page", 99}, {:page, 98}, {"tag", "one"}, {"tag", "two"}],
        receive_timeout: 1234,
        headers: [{"x-client", "retained"}]
      )

    merged =
      ReqDnsimple.Helper.merge(original,
        method: :get,
        url: "/:account_id/domains",
        path_params: [account_id: 1010],
        params: %{page: 2},
        headers: [{"x-operation", "added"}]
      )

    assert merged.options[:params] == [{"tag", "one"}, {"tag", "two"}, {:page, 2}]
    assert merged.options[:receive_timeout] == 1234
    assert merged.options[:auth] == original.options[:auth]
    assert merged.options[:base_url] == original.options[:base_url]
    assert merged.adapter == original.adapter
    assert Req.Request.get_header(merged, "x-client") == ["retained"]
    assert Req.Request.get_header(merged, "x-operation") == ["added"]
    assert ReqDnsimple.Client.with_account(merged, & &1) == 1010

    assert original.options[:params] == [
             {"page", 99},
             {:page, 98},
             {"tag", "one"},
             {"tag", "two"}
           ]
  end

  test "appending a URL merges query parameters once while retaining path parameters" do
    original =
      Req.new(
        url: "https://proxy.example/gateway",
        params: %{"page" => 99, "trace" => "retained"},
        path_params: [account_id: 1010]
      )

    appended =
      ReqDnsimple.Helper.append(original,
        url: "/:account_id/zones/:zone",
        params: [page: 2],
        path_params: [zone: "example.com"]
      )

    assert appended.url.path == "/gateway/:account_id/zones/:zone"
    assert appended.options[:params] == %{:page => 2, "trace" => "retained"}
    assert appended.options[:path_params] == [account_id: 1010, zone: "example.com"]
    assert original.options[:params] == %{"page" => 99, "trace" => "retained"}
  end

  defp request(params) do
    client(404, %{"message" => "offline response"}, self(), [
      {"x-request-id", "query-probe"}
    ])
    |> ReqDnsimple.for_account(1010)
    |> Req.merge(params: params)
  end

  defp params(:keyword, values), do: values
  defp params(:map, values), do: Map.new(values)

  defp params(:string_map, values),
    do: Map.new(values, fn {key, value} -> {to_string(key), value} end)

  defp params(:tuple_list, values),
    do: Enum.map(values, fn {key, value} -> {to_string(key), value} end)
end
