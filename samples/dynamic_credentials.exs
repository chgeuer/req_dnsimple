Code.require_file("support/setup.exs", __DIR__)
alias ReqDnsimple.Samples

zone = Samples.env!("DNSIMPLE_ZONE")

# Neither construction nor Req.merge invokes this callback. Each request does.
token = fn -> {:bearer, Samples.env!("DNSIMPLE_TOKEN")} end

client =
  ReqDnsimple.new_client(
    token,
    [
      account_id: Samples.env!("DNSIMPLE_ACCOUNT_ID"),
      headers: [{"x-example-client", "req-dnsimple-samples"}]
    ] ++ Samples.transport_options()
  )
  |> Req.merge(receive_timeout: 30_000)

{zones, _metadata} = ReqDnsimple.Zone.list!(client, per_page: 5)
IO.puts("First credential resolution: #{length(zones)} zones on the first page")

{records, _metadata} =
  client
  |> ReqDnsimple.ZoneRecord.list_page(zone, type: "A", per_page: 5)
  |> ReqDnsimple.unwrap!()

IO.puts("Second credential resolution: #{length(records)} A records on the first page")
