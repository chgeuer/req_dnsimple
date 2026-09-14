Code.require_file("support/setup.exs", __DIR__)
alias ReqDnsimple.Samples

zone = Samples.env!("DNSIMPLE_ZONE")
client = Samples.client()

filters = [
  name_like: System.get_env("DNSIMPLE_RECORD_NAME_LIKE", "www"),
  type: System.get_env("DNSIMPLE_RECORD_TYPE", "A"),
  sort: [name: :asc, id: :asc],
  per_page: 25
]

{records, pagination} =
  client
  |> ReqDnsimple.ZoneRecord.list_page(zone, filters ++ [page: 1])
  |> ReqDnsimple.unwrap!()

IO.puts(
  "Page #{pagination["current_page"]}/#{pagination["total_pages"]}: " <>
    "#{length(records)} matching records"
)

# list_all starts at page one; passing page: is a validation error.
all_records =
  client
  |> ReqDnsimple.ZoneRecord.list_all(zone, filters)
  |> ReqDnsimple.unwrap!()

IO.puts("All pages: #{length(all_records)} matching records (contents not printed)")
