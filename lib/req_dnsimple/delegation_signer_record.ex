defmodule ReqDnsimple.DelegationSignerRecord do
  @moduledoc """
  Operations for domain delegation-signer records.

  Delete one delegation-signer record:

      :ok =
        ReqDnsimple.DelegationSignerRecord.delete(
          client,
          1010,
          "example.test",
          1
        )

  Deletion removes only the selected registry delegation-signer record. It does
  not disable DNSSEC or delete hosted-zone records.
  """

  @delete_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    ds_record_id: [type: :integer, required: true]
  ]

  @doc """
  Deletes one delegation-signer record from a domain.

  Returns `:ok` for the API's empty HTTP 204 response. Registry refusals,
  missing records, other HTTP responses, and transport failures are returned
  as explicit error tuples.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, domain, ds_record_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               ds_record_id: ds_record_id
             ],
             @delete_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain/ds_records/:ds_record_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            ds_record_id: ds_record_id
          ]
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
