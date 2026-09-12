defmodule ReqDnsimple.Dnssec do
  @moduledoc """
  Operations for domain DNSSEC.

  Disable DNSSEC for a domain:

      :ok = ReqDnsimple.Dnssec.disable(client, 1010, "example.test")

  For hosted-only domains, remove registry delegation-signer records before
  disabling DNSSEC. This operation does not remove those records automatically.
  """

  @disable_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @doc """
  Disables DNSSEC for a domain.

  Returns `:ok` only for the API's empty HTTP 204 response. HTTP 428 when DNSSEC
  is not currently enabled, other HTTP responses, and transport failures are
  returned as explicit error tuples.
  """
  @spec disable(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          :ok | {:error, term()}
  def disable(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @disable_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain/dnssec",
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
