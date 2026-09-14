defmodule ReqDnsimple.AccountScopeOperationsTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @inventory_path Path.expand("../docs/audit/operation-inventory.json", __DIR__)
  @external_resource @inventory_path
  @inventory @inventory_path |> File.read!() |> Jason.decode!()
  @operations Enum.filter(
                @inventory["operations"],
                &(&1["in_scope"] and String.contains?(&1["path"], "{account}"))
              )
  @interfaces Enum.flat_map(@operations, & &1["scoped_interfaces"])
  @error_body %{"message" => "offline account scope probe"}
  @record_attrs [name: "www", type: "A", content: "192.0.2.1", ttl: 0]

  @attrs %{
    {"ReqDnsimple.Certificate", "purchase_letsencrypt"} => [auto_renew: false],
    {"ReqDnsimple.Certificate", "purchase_letsencrypt_renewal"} => [auto_renew: false],
    {"ReqDnsimple.Contact", "create"} => [
      first_name: "Test",
      last_name: "Contact",
      address1: "1 Example Street",
      city: "Roma",
      state_province: "RM",
      postal_code: "00100",
      country: "IT",
      email: "contact@example.test",
      phone: "+12025550123"
    ],
    {"ReqDnsimple.Contact", "update"} => [label: "Scoped contact"],
    {"ReqDnsimple.DelegationSignerRecord", "create"} => [
      algorithm: "13",
      digest: "offline-digest",
      digest_type: "2",
      keytag: "42"
    ],
    {"ReqDnsimple.Domain", "create"} => [name: "example.test"],
    {"ReqDnsimple.DomainPush", "initiate"} => [new_account_identifier: "2020"],
    {"ReqDnsimple.DomainPush", "accept"} => [contact_id: 42],
    {"ReqDnsimple.EmailForward", "create"} => [
      alias_name: "mail",
      destination_email: "mail@example.test"
    ],
    {"ReqDnsimple.PrimaryServer", "create"} => [name: "primary", ip: "192.0.2.1", port: 53],
    {"ReqDnsimple.PrimaryServer", "link"} => [zone: "example.test"],
    {"ReqDnsimple.PrimaryServer", "unlink"} => [zone: "example.test"],
    {"ReqDnsimple.RegistrantChange", "create"} => [domain_id: 42, contact_id: 43],
    {"ReqDnsimple.Registrar", "renew"} => [period: 1],
    {"ReqDnsimple.Registrar", "register"} => [registrant_id: 42, auto_renew: false],
    {"ReqDnsimple.Registrar", "transfer"} => [registrant_id: 42, auth_code: "offline-code"],
    {"ReqDnsimple.Registrar", "restore"} => [premium_price: "10.00"],
    {"ReqDnsimple.Registrar", "change_delegation"} => [name_servers: ["ns1.example.test"]],
    {"ReqDnsimple.SecondaryZone", "create"} => [name: "example.test"],
    {"ReqDnsimple.Service", "apply"} => [settings: %{"app" => "offline"}],
    {"ReqDnsimple.Template", "create"} => [sid: "scope-template", name: "Scope template"],
    {"ReqDnsimple.Template", "update"} => [description: "Scoped template"],
    {"ReqDnsimple.TemplateRecord", "create"} => @record_attrs,
    {"ReqDnsimple.Webhook", "create"} => [url: "https://hooks.example.test/events"],
    {"ReqDnsimple.Zone", "update_ns_records"} => [ns_names: ["ns1.example.test"]],
    {"ReqDnsimple.ZoneRecord", "create"} => @record_attrs,
    {"ReqDnsimple.ZoneRecord", "batch_change"} => [
      creates: [@record_attrs],
      updates: [[id: 42, ttl: 0]],
      deletes: [[id: 43]]
    ],
    {"ReqDnsimple.ZoneRecord", "update"} => [ttl: 0, integrated_zones: []],
    {"ReqDnsimple", "create_zone_record"} => @record_attrs
  }

  test "all 95 account-path operations declare documented, typed scoped interfaces" do
    assert length(@operations) == 95

    for operation <- @operations do
      assert operation["scoped_interfaces"] != []

      for interface <- operation["scoped_interfaces"] do
        module = module(interface)
        assert Code.ensure_loaded?(module)
        function = String.to_existing_atom(interface["function"])
        assert interface["arity"] == length(interface["arguments"])
        assert interface["arity"] == Enum.max(interface["arities"])
        refute "account_id" in interface["arguments"]

        {:ok, specs} = Code.Typespec.fetch_specs(module)
        {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

        for arity <- interface["arities"] do
          assert function_exported?(module, function, arity)
          assert List.keymember?(specs, {function, arity}, 0)

          assert Enum.any?(docs, fn
                   {{:function, ^function, ^arity}, _, _, %{"en" => doc}, _} ->
                     String.trim(doc) != ""

                   _ ->
                     false
                 end)
        end
      end
    end
  end

  describe "account-scoped operation parity" do
    for interface <- @interfaces, arity <- interface["arities"] do
      label = "#{interface["module"]}.#{interface["function"]}/#{arity}"

      test "#{label} preserves the explicit-account request and result" do
        interface = unquote(Macro.escape(interface))
        args = arguments(interface) |> Enum.take(unquote(arity) - 1)

        req =
          client(418, @error_body)
          |> Req.merge(
            base_url: "https://proxy.example/gateway/v2",
            receive_timeout: 4321,
            headers: [{"x-scope-probe", "preserved"}]
          )

        legacy = ReqDnsimple.for_account(req, 9090)
        scoped = ReqDnsimple.for_account(req, "1010")

        expected = invoke(interface, [legacy, 1010 | args])
        assert_receive {:request, explicit_request}

        assert invoke(interface, [scoped | args]) == expected
        assert_receive {:request, scoped_request}
        refute_received {:request, _request}

        assert String.starts_with?(scoped_request.url.path, "/gateway/v2/1010/")
        assert scoped_request.url == explicit_request.url
        assert scoped_request.method == explicit_request.method
        assert scoped_request.headers == explicit_request.headers
        assert scoped_request.body == explicit_request.body
        assert scoped_request.adapter == explicit_request.adapter
        assert scoped_request.options == explicit_request.options
      end

      test "#{label} fails without account scope before authentication or HTTP" do
        interface = unquote(Macro.escape(interface))
        args = arguments(interface) |> Enum.take(unquote(arity) - 1)

        req =
          ReqDnsimple.new_unscoped_client(fn ->
            flunk("an unscoped operation must not resolve credentials")
          end)

        if String.ends_with?(interface["function"], "!") do
          error =
            assert_raise ReqDnsimple.Error, fn ->
              apply(module(interface), String.to_existing_atom(interface["function"]), [
                req | args
              ])
            end

          assert error.reason == :missing_account_id
        else
          assert invoke(interface, [req | args]) == {:error, :missing_account_id}
        end

        refute_received {:request, _request}
      end
    end
  end

  defp invoke(interface, args) do
    module = module(interface)
    function = String.to_existing_atom(interface["function"])

    if String.ends_with?(interface["function"], "!") do
      error =
        assert_raise ReqDnsimple.Error, fn ->
          apply(module, function, args)
        end

      {:raised, error.reason}
    else
      apply(module, function, args)
    end
  end

  defp module(interface) do
    module = Module.concat(String.split(interface["module"], "."))
    assert Code.ensure_loaded?(module)
    module
  end

  defp arguments(interface) do
    interface["arguments"]
    |> Enum.drop(1)
    |> Enum.map(&argument(&1, interface))
  end

  defp argument("attrs", interface),
    do: Map.fetch!(@attrs, {interface["module"], interface["function"]})

  defp argument("opts", %{"module" => "ReqDnsimple.DomainResearch"}),
    do: [domain: "example.test"]

  defp argument("opts", %{"module" => "ReqDnsimple.DnsAnalytics"}),
    do: [start_date: "2026-09-01", end_date: "2026-09-02", per_page: 1]

  defp argument("opts", _interface), do: []

  defp argument(name, _interface)
       when name in ["zone", "zone_id", "zone_name", "domain", "domain_name"],
       do: "example.test"

  defp argument("service", _interface), do: "scope-service"
  defp argument("template", _interface), do: "scope-template"

  defp argument(name, _interface)
       when name in [
              "certificate_id",
              "contact_id",
              "ds_record_id",
              "email_forward_id",
              "primary_server_id",
              "push_id",
              "record_id",
              "registrant_change_id",
              "renewal_id",
              "webhook_id"
            ],
       do: 42
end
