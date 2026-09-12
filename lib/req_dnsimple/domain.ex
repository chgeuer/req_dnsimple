defmodule ReqDnsimple.Domain do
  @moduledoc """
  DNSimple Domain API functionality.

  ## Example

      ReqDnsimple.Domain.delete(req, 1010, "example.test")
      #=> :ok
  """

  # https://developer.dnsimple.com/v2/domains/

  @delete_domain_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @doc """
  Deletes one domain from an account.

  This irreversible account operation does not delete a registration at the
  registry or produce a refund.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delete_domain_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain",
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
