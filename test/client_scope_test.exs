defmodule ReqDnsimple.ClientScopeTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @tokens ["dnsimple_a_fake-token", "dnsimple_u_fake-token", "opaque-fake-token"]
  @record %{
    "id" => 42,
    "zone_id" => "example.test",
    "parent_id" => nil,
    "name" => "www",
    "content" => "192.0.2.1",
    "ttl" => 0,
    "priority" => nil,
    "type" => "A",
    "regions" => ["global"],
    "system_record" => false,
    "created_at" => "2026-09-01T00:00:00Z",
    "updated_at" => "2026-09-01T00:00:00Z"
  }

  test "both token kinds and opaque tokens use the same normalized account-scoped interface" do
    for token <- @tokens, account_id <- [1010, "1010", "001010"] do
      req =
        ReqDnsimple.new_client(token,
          account_id: account_id,
          adapter: empty_zone_adapter(self())
        )

      assert %Req.Request{} = req
      assert {:ok, []} = ReqDnsimple.Zone.list(req)
      assert_request(:get, "/v2/1010/zones")
    end
  end

  test "scoped construction requires exactly one valid account ID for every token kind" do
    for token <- @tokens do
      assert_raise ArgumentError, ~r/account_id is required/, fn ->
        ReqDnsimple.new_client(token, [])
      end

      assert_raise ArgumentError, ~r/exactly once/, fn ->
        ReqDnsimple.new_client(token, account_id: 1010, account_id: 2020)
      end
    end

    for invalid <- [
          nil,
          0,
          -1,
          1.0,
          "",
          "0",
          "00",
          "-1",
          "+1",
          " 1",
          "1 ",
          "1\n",
          "1x",
          :bad,
          [],
          %{}
        ] do
      assert_raise ArgumentError, ~r/positive integer or a positive numeric string/, fn ->
        ReqDnsimple.new_client("dnsimple_a_fake-token", account_id: invalid)
      end
    end
  end

  test "constructor option containers fail explicitly without exposing credentials" do
    token = "dnsimple_a_do-not-display-this-value"

    for invalid <- [nil, %{}, [:bad], [{:account_id}], [{"account_id", 1010}]],
        constructor <- [&ReqDnsimple.new_client/2, &ReqDnsimple.new_unscoped_client/2] do
      error = assert_raise ArgumentError, fn -> constructor.(token, invalid) end
      assert error.message == "expected client options to be a keyword list"
      refute error.message =~ token
    end
  end

  test "the explicit unscoped constructor rejects account configuration" do
    for account_id <- [1010, nil] do
      assert_raise ArgumentError, ~r/use new_client\/2/, fn ->
        ReqDnsimple.new_unscoped_client("dnsimple_a_fake-token", account_id: account_id)
      end
    end
  end

  test "legacy construction remains unscoped for account and user tokens" do
    for token <- @tokens do
      req =
        ReqDnsimple.new_client(token)
        |> Req.merge(adapter: empty_zone_adapter(self()))

      assert {:error, :missing_account_id} = ReqDnsimple.Zone.list(req)
      refute_received {:request, _request}
      assert {:ok, []} = ReqDnsimple.Zone.list(req, "1010")
      assert_request(:get, "/v2/1010/zones")
    end
  end

  test "constructing and rebinding clients never resolves a token callback" do
    callback = fn -> flunk("configuration must not resolve a credential") end

    for req <- [
          ReqDnsimple.new_client(callback),
          ReqDnsimple.new_client(callback, account_id: 1010),
          ReqDnsimple.new_unscoped_client(callback)
        ] do
      assert %Req.Request{} = ReqDnsimple.for_account(req, "2020")
    end

    assert_raise ArgumentError, fn ->
      ReqDnsimple.new_client(callback, account_id: nil)
    end
  end

  test "dynamic credentials resolve once per request and preserve bearer-tuple callbacks" do
    tokens = ["first-token", {:bearer, "second-token"}]
    agent = start_supervised!({Agent, fn -> tokens end})

    req =
      ReqDnsimple.new_client(
        fn -> Agent.get_and_update(agent, fn [token | rest] -> {token, rest} end) end,
        account_id: 1010,
        adapter: empty_zone_adapter(self())
      )

    other = ReqDnsimple.for_account(req, 2020)
    assert Agent.get(agent, & &1) == tokens

    assert {:ok, []} = ReqDnsimple.Zone.list(req)
    assert_receive {:request, first}
    assert first.url.path == "/v2/1010/zones"
    assert Req.Request.get_header(first, "authorization") == ["Bearer first-token"]

    assert {:ok, []} = ReqDnsimple.Zone.list(other)
    assert_receive {:request, second}
    assert second.url.path == "/v2/2020/zones"
    assert Req.Request.get_header(second, "authorization") == ["Bearer second-token"]
    assert Agent.get(agent, & &1) == []
  end

  test "Req customization and immutable re-scoping preserve authentication and transport" do
    original =
      ReqDnsimple.new_client("dnsimple_u_fake-token",
        account_id: "1010",
        base_url: "https://proxy.example/gateway/v2",
        headers: [{"x-original", "preserved"}],
        receive_timeout: 4321,
        retry: false,
        adapter: empty_zone_adapter(self())
      )
      |> Req.Request.put_private(:sample_context, :preserved)
      |> Req.merge(headers: [{"x-added", "preserved"}])

    other = ReqDnsimple.for_account(original, "2020")

    for {req, account_id} <- [{original, 1010}, {other, 2020}, {original, 1010}] do
      assert {:ok, []} = ReqDnsimple.Zone.list(req)
      assert_receive {:request, request}
      assert request.url.host == "proxy.example"
      assert request.url.path == "/gateway/v2/#{account_id}/zones"
      assert request.options[:receive_timeout] == 4321
      assert request.options[:retry] == false
      assert Req.Request.get_header(request, "authorization") == ["Bearer dnsimple_u_fake-token"]
      assert Req.Request.get_header(request, "x-original") == ["preserved"]
      assert Req.Request.get_header(request, "x-added") == ["preserved"]
      assert Req.Request.get_private(request, :sample_context) == :preserved
      refute Map.has_key?(request.options, :account_id)
    end
  end

  test "for_account validates IDs without changing the original request" do
    original = client(200, %{"data" => []}) |> ReqDnsimple.for_account(1010)

    for invalid <- [nil, 0, -1, "", "1.0", "other"] do
      assert_raise ArgumentError, fn -> ReqDnsimple.for_account(original, invalid) end
    end

    assert {:ok, []} = ReqDnsimple.Zone.list(original)
    assert_request(:get, "/v2/1010/zones")
  end

  test "explicit-account overloads take precedence for only that call" do
    req = client(200, %{"data" => []}) |> ReqDnsimple.for_account(1010)

    assert {:ok, []} = ReqDnsimple.Zone.list(req, "2020")
    assert_request(:get, "/v2/2020/zones")
    assert [] = ReqDnsimple.list_zones!(req, "3030")
    assert_request(:get, "/v2/3030/zones")
    assert {:ok, []} = ReqDnsimple.list_zones(req, 4040, name_like: "example")
    assert_request(:get, "/v2/4040/zones", %{"name_like" => "example"})
    assert {:ok, []} = ReqDnsimple.Zone.list(req)
    assert_request(:get, "/v2/1010/zones")
  end

  test "root shortcuts accept the same scoped filters and pagination options" do
    req = client(200, %{"data" => []}) |> ReqDnsimple.for_account(1010)

    assert {:ok, []} = ReqDnsimple.list_zones(req, name_like: "example", per_page: 7)
    assert_request(:get, "/v2/1010/zones", %{"name_like" => "example", "per_page" => "7"})

    assert [] = ReqDnsimple.list_zones!(req, sort: [:name])
    assert_request(:get, "/v2/1010/zones", %{"sort" => "name:asc"})

    assert {:ok, []} = ReqDnsimple.list_contacts(req, sort: [label: :desc])
    assert_request(:get, "/v2/1010/contacts", %{"sort" => "label:desc"})

    assert {:ok, []} = ReqDnsimple.list_billing_charges(req, sort: [invoiced: :desc])
    assert_request(:get, "/v2/1010/billing/charges", %{"sort" => "invoiced:desc"})
  end

  test "scoped keyword-taking overloads reject malformed containers without HTTP" do
    req = ReqDnsimple.new_client("dnsimple_a_fake-token", account_id: 1010)

    for operation <- [
          &ReqDnsimple.Zone.list(req, &1),
          &ReqDnsimple.Zone.list_page(req, &1),
          &ReqDnsimple.Zone.list_all(req, &1),
          &ReqDnsimple.ZoneRecord.list(req, "example.test", &1),
          &ReqDnsimple.ZoneRecord.list_page(req, "example.test", &1),
          &ReqDnsimple.ZoneRecord.list_all(req, "example.test", &1),
          &ReqDnsimple.ZoneRecord.create(req, "example.test", &1),
          &ReqDnsimple.ZoneRecord.update(req, "example.test", 42, &1),
          &ReqDnsimple.Certificate.purchase_letsencrypt(req, "example.test", &1),
          &ReqDnsimple.Service.apply(req, "example.test", "service", &1)
        ],
        invalid <- [nil, %{}, [:bad], [{:bad}]] do
      assert {:error, %NimbleOptions.ValidationError{}} = operation.(invalid)
    end
  end

  test "scoped record mutations retain typed successes, explicit zeroes, and bodyless deletion" do
    req =
      ReqDnsimple.new_client("dnsimple_a_fake-token",
        account_id: 1010,
        adapter: fn request ->
          send(self(), {:request, request})

          response =
            case request.method do
              :post -> %Req.Response{status: 201, body: %{"data" => @record}}
              :get -> %Req.Response{status: 200, body: %{"data" => @record}}
              :patch -> %Req.Response{status: 200, body: %{"data" => @record}}
              :delete -> %Req.Response{status: 204, body: nil}
            end

          {request, response}
        end
      )

    assert {:ok, %ReqDnsimple.ZoneRecord{id: 42, ttl: 0}} =
             ReqDnsimple.create_zone_record(req, "example.test",
               name: "www",
               type: "A",
               content: "192.0.2.1",
               ttl: 0
             )

    assert_request(:post, "/v2/1010/zones/example.test/records", %{}, %{
      name: "www",
      type: "A",
      content: "192.0.2.1",
      ttl: 0
    })

    assert {:ok, %ReqDnsimple.ZoneRecord{id: 42}} =
             ReqDnsimple.get_zone_record(req, "example.test", 42)

    assert_request(:get, "/v2/1010/zones/example.test/records/42")

    assert {:ok, %ReqDnsimple.ZoneRecord{id: 42}} =
             ReqDnsimple.ZoneRecord.update(req, "example.test", 42,
               ttl: 0,
               integrated_zones: []
             )

    assert_request(:patch, "/v2/1010/zones/example.test/records/42", %{}, %{
      ttl: 0,
      integrated_zones: []
    })

    assert :ok = ReqDnsimple.delete_zone_record(req, "example.test", 42)
    assert_request(:delete, "/v2/1010/zones/example.test/records/42")
  end

  test "overlapping optional-attribute forms distinguish integer resource IDs from options" do
    req = client(204, nil) |> ReqDnsimple.for_account(1010)

    assert :ok = ReqDnsimple.Service.apply(req, 500, 600)
    assert_request(:post, "/v2/1010/domains/500/services/600")

    assert :ok = ReqDnsimple.Service.apply(req, 2020, 500, 600)
    assert_request(:post, "/v2/2020/domains/500/services/600")

    assert :ok = ReqDnsimple.Service.apply(req, 500, 600, settings: %{"app" => "offline"})

    assert_request(:post, "/v2/1010/domains/500/services/600", %{}, %{
      settings: %{"app" => "offline"}
    })
  end

  test "missing scope produces a descriptive bang error" do
    req = ReqDnsimple.new_unscoped_client("dnsimple_a_fake-token")

    for operation <- [&ReqDnsimple.Zone.list!/1, &ReqDnsimple.list_zones!/1] do
      error =
        assert_raise ReqDnsimple.Error, ~r/account_id is required/, fn -> operation.(req) end

      assert error.reason == :missing_account_id
    end
  end

  test "account-token identity discovery explicitly binds the returned account ID" do
    discovery =
      client(200, %{"data" => %{"user" => nil, "account" => %{"id" => 1010}}})
      |> Req.merge(auth: {:bearer, "dnsimple_a_fake-token"})

    assert {:account, %{"id" => id}} = ReqDnsimple.whoami(discovery)
    assert_request(:get, "/v2/whoami")

    selected =
      discovery
      |> ReqDnsimple.for_account(id)
      |> Req.merge(adapter: empty_zone_adapter(self()))

    assert {:ok, []} = ReqDnsimple.Zone.list(selected)
    assert_request(:get, "/v2/1010/zones")
    assert {:error, :missing_account_id} = ReqDnsimple.Zone.list(discovery)
  end

  test "global identity and catalog operations ignore selected account scope" do
    req = client(418, %{"message" => "offline global request"}) |> ReqDnsimple.for_account(1010)

    for {operation, path} <- [
          {&ReqDnsimple.whoami/1, "/v2/whoami"},
          {&ReqDnsimple.Account.list/1, "/v2/accounts"},
          {&ReqDnsimple.Tld.get(&1, "com"), "/v2/tlds/com"},
          {&ReqDnsimple.Tld.list_page/1, "/v2/tlds"},
          {&ReqDnsimple.Tld.list_extended_attributes(&1, "com"),
           "/v2/tlds/com/extended_attributes"},
          {&ReqDnsimple.Service.get(&1, "service"), "/v2/services/service"},
          {&ReqDnsimple.Service.list_page/1, "/v2/services"}
        ] do
      assert {:error, _reason} = operation.(req)
      assert_request(:get, path)
    end
  end

  test "OAuth exchange ignores account scope and does not evaluate inherited credentials" do
    req =
      ReqDnsimple.new_client(
        fn -> flunk("OAuth exchange must not resolve the bearer callback") end,
        account_id: 1010,
        adapter: fn request ->
          send(self(), {:request, request})
          {request, %Req.Response{status: 400, body: %{"error" => "invalid_grant"}}}
        end
      )

    assert {:error, _reason} =
             ReqDnsimple.OAuth.exchange_code(req,
               client_id: "offline-client",
               code: "offline-code",
               grant_type: "authorization_code",
               code_verifier: String.duplicate("a", 43)
             )

    assert_receive {:request, request}
    assert request.url.path == "/v2/oauth/access_token"
    assert Req.Request.get_header(request, "authorization") == []
  end

  test "scoped complete enumeration retains account, filters, ordering, and typed records" do
    req =
      ReqDnsimple.new_client("dnsimple_a_fake-token",
        account_id: "1010",
        adapter: fn request ->
          send(self(), {:request, request})

          page =
            request.url.query |> URI.decode_query() |> Map.fetch!("page") |> String.to_integer()

          body = %{
            "data" => [Map.put(@record, "id", page)],
            "pagination" => %{
              "current_page" => page,
              "per_page" => 1,
              "total_entries" => 2,
              "total_pages" => 2
            }
          }

          {request, %Req.Response{status: 200, body: body}}
        end
      )

    assert {:ok, [%ReqDnsimple.ZoneRecord{id: 1}, %ReqDnsimple.ZoneRecord{id: 2}]} =
             ReqDnsimple.ZoneRecord.list_all(req, "example.test",
               type: "A",
               sort: [:name],
               per_page: 1
             )

    for page <- 1..2 do
      assert_request(:get, "/v2/1010/zones/example.test/records", %{
        "page" => to_string(page),
        "per_page" => "1",
        "type" => "A",
        "sort" => "name:asc"
      })
    end

    refute_received {:request, _request}
  end

  defp empty_zone_adapter(test_pid) do
    fn request ->
      send(test_pid, {:request, request})
      {request, %Req.Response{status: 200, body: %{"data" => []}}}
    end
  end
end
