Code.require_file("support/setup.exs", __DIR__)
alias ReqDnsimple.Samples

# Use DNSimple sandbox and a disposable test zone. Never select a record to delete from a list.
zone = Samples.mutation_zone!()
client = Samples.client()
name = "_req-dnsimple-sample-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

IO.puts("Creating #{name} in test zone #{zone}; keep this name if the create response is lost")

created =
  client
  |> ReqDnsimple.ZoneRecord.create(zone,
    name: name,
    type: "TXT",
    content: "req_dnsimple sample: created",
    ttl: 60
  )
  |> ReqDnsimple.unwrap!()

IO.puts("Created sample record #{created.id} (#{name}) in test zone #{zone}")

# Keep the error tuple until after cleanup, so an update failure still triggers deletion.
update_result =
  ReqDnsimple.ZoneRecord.update(client, zone, created.id,
    content: "req_dnsimple sample: updated",
    ttl: 120
  )

cleanup_result = ReqDnsimple.ZoneRecord.delete(client, zone, created.id)

case {update_result, cleanup_result} do
  {{:ok, _updated}, :ok} ->
    IO.puts("Updated and deleted only the newly created sample record #{created.id}")

  {{:error, _reason} = error, :ok} ->
    IO.puts(:stderr, "Update failed; the newly created sample record was deleted")
    ReqDnsimple.unwrap!(error)

  {operation_result, {:error, cleanup_reason}} ->
    IO.puts(
      :stderr,
      "Cleanup failed: check sample record #{created.id} (#{name}) in test zone #{zone}. " <>
        "Both operation and cleanup outcomes are retained in ReqDnsimple.Error.reason."
    )

    ReqDnsimple.unwrap!(
      {:error,
       {:sample_cleanup_failed,
        %{
          zone: zone,
          record_id: created.id,
          operation_result: operation_result,
          cleanup_reason: cleanup_reason
        }}}
    )
end
