Code.require_file("support/setup.exs", __DIR__)
alias ReqDnsimple.Samples

discovery = Samples.unscoped_client()
accounts = Samples.accounts!(discovery)

IO.puts("Available account IDs (choose explicitly; these are not user IDs):")
Enum.each(accounts, fn account -> IO.puts("  #{account.id}") end)

selected_id =
  "DNSIMPLE_ACCOUNT_ID"
  |> Samples.env!()
  |> Samples.positive_id!("DNSIMPLE_ACCOUNT_ID")

account = Samples.select_account!(accounts, selected_id)
client = ReqDnsimple.for_account(discovery, account.id)

zones = ReqDnsimple.Zone.list!(client, per_page: 20)
IO.puts("Selected account #{account.id}; first page contains #{length(zones)} zones")
