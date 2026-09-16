defmodule ReqDnsimple.KeywordContainerTest do
  use ExUnit.Case, async: true

  test "explicit-account keyword-taking interfaces reject malformed containers without requesting" do
    req = ReqDnsimple.new_client("dnsimple_u_fake-token")

    operations = [
      &ReqDnsimple.Zone.list(&1, 1010, &2),
      &ReqDnsimple.Contact.list(&1, 1010, &2),
      &ReqDnsimple.BillingCharge.list(&1, 1010, &2),
      &ReqDnsimple.ZoneRecord.list(&1, 1010, "example.com", &2),
      &ReqDnsimple.ZoneRecord.create(&1, 1010, "example.com", &2),
      &ReqDnsimple.ZoneRecord.update(&1, 1010, "example.com", 42, &2),
      &ReqDnsimple.Zone.list_page(&1, 1010, &2),
      &ReqDnsimple.Zone.list_all(&1, 1010, &2),
      &ReqDnsimple.Contact.list_page(&1, 1010, &2),
      &ReqDnsimple.Contact.list_all(&1, 1010, &2),
      &ReqDnsimple.BillingCharge.list_page(&1, 1010, &2),
      &ReqDnsimple.BillingCharge.list_all(&1, 1010, &2),
      &ReqDnsimple.ZoneRecord.list_page(&1, 1010, "example.com", &2),
      &ReqDnsimple.ZoneRecord.list_all(&1, 1010, "example.com", &2)
    ]

    for operation <- operations, malformed <- [[:invalid], [{:name}]] do
      assert {:error,
              %ReqDnsimple.Error{
                reason: %NimbleOptions.ValidationError{
                  message: "expected a keyword list",
                  value: ^malformed
                },
                metadata: nil
              }} = operation.(req, malformed)
    end

    refute_received {:request, _request}
  end
end
