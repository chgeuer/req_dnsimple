Code.require_file("support/setup.exs", __DIR__)
alias ReqDnsimple.Samples

discovery = Samples.unscoped_client()

client =
  case ReqDnsimple.whoami(discovery) do
    {:ok, {{:account, %{"id" => id}}, _metadata}} ->
      ReqDnsimple.for_account(discovery, id)

    {:ok, {{:user, _user}, _metadata}} ->
      raise ArgumentError,
            "whoami returned a user; run samples/discover_user.exs and select an account"

    {:ok, {{:unknown_token, _body}, _metadata}} ->
      raise ArgumentError, "whoami did not identify exactly one account"

    {:error, %ReqDnsimple.Error{}} = error ->
      ReqDnsimple.unwrap!(error)
  end

{zones, _metadata} = ReqDnsimple.Zone.list!(client, per_page: 20)
IO.puts("Account discovered through whoami; first page contains #{length(zones)} zones")
