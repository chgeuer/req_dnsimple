defmodule ReqDnsimple.Registrar do
  @moduledoc """
  DNSimple registrar API functionality.

  ## Example

      ReqDnsimple.Registrar.authorize_transfer_out(req, 1010, "example.test")
      #=> :ok
  """

  # https://developer.dnsimple.com/v2/registrar/#authorizeDomainTransferOut

  @path_schema [
    account_id: [type: :integer, required: true],
    domain_name: [type: :string, required: true]
  ]

  @doc """
  Authorizes a domain transfer out.

  DNSimple unlocks the domain and emails the authorization code to the
  administrative contact. This function sends exactly one request; it does not
  retrieve the code, contact, or domain, or initiate a transfer.

  Returns `:ok` only for the API's empty HTTP 204 response. Other HTTP responses
  and transport failures are returned as explicit error tuples.
  """
  @spec authorize_transfer_out(Req.Request.t(), ReqDnsimple.account_id(), String.t()) ::
          :ok | {:error, term()}
  def authorize_transfer_out(req, account_id, domain_name) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain_name: domain_name],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/registrar/domains/:domain_name/authorize_transfer_out",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain_name: domain_name]
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
