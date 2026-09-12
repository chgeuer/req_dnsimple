defmodule ReqDnsimple.EmailForward do
  @moduledoc """
  Operations for domain email forwards.

  Delete one email forward:

      :ok =
        ReqDnsimple.EmailForward.delete(
          client,
          1010,
          "example.test",
          1
        )

  Deletion removes only the selected email forward. It does not send mail or
  modify the domain's MX records.
  """

  @delete_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    email_forward_id: [type: :integer, required: true]
  ]

  @doc """
  Deletes one email forward from a domain.

  Returns `:ok` for the API's empty HTTP 204 response. Deletion refusals,
  missing forwards, other HTTP responses, and transport failures are returned
  as explicit error tuples.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, domain, email_forward_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               email_forward_id: email_forward_id
             ],
             @delete_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain/email_forwards/:email_forward_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            email_forward_id: email_forward_id
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
