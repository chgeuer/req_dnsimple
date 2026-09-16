Code.require_file("support/setup.exs", __DIR__)
alias ReqDnsimple.Samples

zone_name = Samples.env!("DNSIMPLE_ZONE")
client = Samples.client()

{zones, _metadata} = ReqDnsimple.list_zones!(client, sort: [name: :asc], per_page: 20)
IO.puts("First page: #{length(zones)} zones")

{zone, _metadata} =
  client
  |> ReqDnsimple.Zone.get(zone_name)
  |> ReqDnsimple.unwrap!()

IO.puts("Zone #{zone.name}: active=#{zone.active}")

{records, metadata} =
  client
  |> ReqDnsimple.ns_records(zone_name)
  |> ReqDnsimple.unwrap!()

IO.puts("Apex NS records: #{length(records)} (#{length(metadata.pages)} response pages)")
