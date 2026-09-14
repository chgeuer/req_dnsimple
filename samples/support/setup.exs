defmodule ReqDnsimple.Samples do
  @moduledoc false

  def env!(name) do
    case System.get_env(name) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          raise ArgumentError, "Set a non-empty #{name} before running this sample"
        end

        value

      nil ->
        raise ArgumentError, "Set #{name} before running this sample"
    end
  end

  def positive_id!(value, source) do
    if String.match?(value, ~r/\A[0-9]+\z/) do
      id = String.to_integer(value)

      if id > 0 do
        id
      else
        raise ArgumentError, "#{source} must contain a positive account ID"
      end
    else
      raise ArgumentError, "#{source} must contain an all-digit positive account ID"
    end
  end

  def transport_options do
    [
      base_url: System.get_env("DNSIMPLE_BASE_URL", "https://api.sandbox.dnsimple.com/v2"),
      retry: false,
      receive_timeout: 15_000
    ]
  end

  def client do
    ReqDnsimple.new_client(
      env!("DNSIMPLE_TOKEN"),
      [account_id: env!("DNSIMPLE_ACCOUNT_ID")] ++ transport_options()
    )
  end

  def unscoped_client do
    ReqDnsimple.new_unscoped_client(env!("DNSIMPLE_TOKEN"), transport_options())
  end

  def accounts!(client) do
    case ReqDnsimple.Account.list(client) do
      accounts when is_list(accounts) -> accounts
      {:error, _reason} = error -> ReqDnsimple.unwrap!(error)
    end
  end

  def select_account!(accounts, selected_id) do
    Enum.find(accounts, &(&1.id == selected_id)) ||
      raise ArgumentError, "The selected account ID is not in Account.list/1"
  end

  def mutation_zone! do
    unless System.get_env("DNSIMPLE_ALLOW_MUTATIONS") == "true" do
      raise ArgumentError,
            "Mutation sample disabled: use DNSimple sandbox, set DNSIMPLE_TEST_ZONE, " <>
              "and explicitly set DNSIMPLE_ALLOW_MUTATIONS=true"
    end

    env!("DNSIMPLE_TEST_ZONE")
  end
end
