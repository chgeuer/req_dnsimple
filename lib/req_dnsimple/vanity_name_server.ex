defmodule ReqDnsimple.VanityNameServer do
  @moduledoc """
  DNSimple vanity name-server API functionality.

  ## Example

      ReqDnsimple.VanityNameServer.disable(req, 1010, "example.test")
      #=> :ok
  """

  # https://developer.dnsimple.com/v2/vanity/

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @doc """
  Disables vanity name-server records for a domain by name or ID.

  This removes the vanity A and AAAA configuration in one request. It does not
  change the domain's registrar delegation or delete records individually.
  """
  @spec disable(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          :ok | {:error, term()}
  def disable(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/vanity/:domain",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 204}} ->
          :ok

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end
end
