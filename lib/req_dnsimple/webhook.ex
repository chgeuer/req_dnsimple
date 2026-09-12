defmodule ReqDnsimple.Webhook do
  @moduledoc """
  DNSimple webhook operations.

  Deregister a webhook endpoint by numeric ID:

      :ok = ReqDnsimple.Webhook.delete(client, 1010, 1)

  Deletion sends exactly one bodyless request. It does not contact the callback
  URL, inspect deliveries, or discover registrations first.
  """

  @path_schema [
    account_id: [type: :integer, required: true],
    webhook_id: [type: {:or, [:integer, :string]}, required: true]
  ]

  @doc """
  Deregisters a webhook endpoint by integer or numeric-string ID.

  Returns `:ok` only for HTTP 204.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), integer() | binary()) ::
          :ok | {:error, term()}
  def delete(req, account_id, webhook_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, webhook_id: webhook_id],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/webhooks/:webhook_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, webhook_id: webhook_id],
          retry: false
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
