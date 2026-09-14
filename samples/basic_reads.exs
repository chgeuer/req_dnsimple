Code.require_file("support/setup.exs", __DIR__)
alias ReqDnsimple.Samples

zone_name = Samples.env!("DNSIMPLE_ZONE")
client = Samples.client()

zones = ReqDnsimple.list_zones!(client, sort: [name: :asc], per_page: 20)
IO.puts("First page: #{length(zones)} zones")

zone =
  client
  |> ReqDnsimple.Zone.get(zone_name)
  |> ReqDnsimple.unwrap!()

IO.puts("Zone #{zone.name}: active=#{zone.active}")

# ns_records returns a bare list, so do not pass it to unwrap!/1.
case ReqDnsimple.ns_records(client, zone_name) do
  records when is_list(records) ->
    IO.puts("Apex NS records: #{length(records)}")

  {:error, _reason} = error ->
    ReqDnsimple.unwrap!(error)
end
