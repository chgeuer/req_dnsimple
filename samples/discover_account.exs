Code.require_file("support/setup.exs", __DIR__)
alias ReqDnsimple.Samples

discovery = Samples.unscoped_client()

client =
  case ReqDnsimple.whoami(discovery) do
    {:account, %{"id" => id}} ->
      ReqDnsimple.for_account(discovery, id)

    {:user, _user} ->
      raise ArgumentError,
            "whoami returned a user; run samples/discover_user.exs and select an account"

    {:unknown_token, _body} ->
      raise ArgumentError, "whoami did not identify exactly one account"

    {:error, _reason} = error ->
      ReqDnsimple.unwrap!(error)
  end

zones = ReqDnsimple.Zone.list!(client, per_page: 20)
IO.puts("Account discovered through whoami; first page contains #{length(zones)} zones")
