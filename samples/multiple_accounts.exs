Code.require_file("support/setup.exs", __DIR__)
alias ReqDnsimple.Samples

account_ids =
  Samples.env!("DNSIMPLE_ACCOUNT_IDS")
  |> String.split(",")
  |> Enum.map(fn value ->
    value
    |> String.trim()
    |> Samples.positive_id!("DNSIMPLE_ACCOUNT_IDS")
  end)
  |> Enum.uniq()

if length(account_ids) < 2 do
  raise ArgumentError, "DNSIMPLE_ACCOUNT_IDS must name at least two distinct accounts"
end

discovery = Samples.unscoped_client()

# Re-scoping is local and immutable; it does not verify token permissions.
clients = Map.new(account_ids, &{&1, ReqDnsimple.for_account(discovery, &1)})

{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}} =
  ReqDnsimple.Zone.list(discovery)

Enum.each(account_ids, fn account_id ->
  client = Map.fetch!(clients, account_id)
  {zones, _metadata} = ReqDnsimple.Zone.list!(client, per_page: 20)
  IO.puts("Account #{account_id}: #{length(zones)} zones on the first page")
end)
