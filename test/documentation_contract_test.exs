defmodule ReqDnsimple.DocumentationContractTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)

  test "public guides describe bounded coverage and the versioned inventory states" do
    readme = File.read!(Path.join(@root, "README.md"))
    usage_rules = File.read!(Path.join(@root, "usage-rules.md"))
    inventory = File.read!(Path.join(@root, "docs/audit/operation-inventory.json"))

    refute readme =~ "all DNSimple API operations"
    refute usage_rules =~ "all DNSimple API operations"

    assert readme =~ "docs/audit/operation-inventory.json"
    assert usage_rules =~ "docs/audit/operation-inventory.json"

    for state <- ["existing", "implemented", "pending", "out-of-scope"] do
      assert readme =~ "`#{state}`"
      assert usage_rules =~ "`#{state}`"
      assert inventory =~ ~s("implementation": "#{state}")
    end
  end

  test "functions used by the public examples are exported" do
    exports = [
      {ReqDnsimple, :new_client, 1},
      {ReqDnsimple, :whoami, 1},
      {ReqDnsimple, :ns_records, 3},
      {ReqDnsimple.Zone, :list, 3},
      {ReqDnsimple.Zone, :list_page, 3},
      {ReqDnsimple.Zone, :list_all, 3},
      {ReqDnsimple.ZoneRecord, :list, 4},
      {ReqDnsimple.ZoneRecord, :list_page, 4},
      {ReqDnsimple.ZoneRecord, :list_all, 4},
      {ReqDnsimple.ZoneRecord, :create, 4},
      {ReqDnsimple.ZoneRecord, :update, 5},
      {ReqDnsimple.ZoneRecord, :delete, 4},
      {ReqDnsimple.ZoneRecord, :batch_change, 4},
      {ReqDnsimple.BillingCharge, :list, 3},
      {ReqDnsimple.Contact, :list, 3},
      {ReqDnsimple.Contact, :get, 3}
    ]

    for {module, function, arity} <- exports do
      assert Code.ensure_loaded?(module), "expected #{inspect(module)} to load"

      assert function_exported?(module, function, arity),
             "expected #{inspect(module)}.#{function}/#{arity} to be exported"
    end
  end
end
