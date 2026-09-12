defmodule ReqDnsimple.DomainPush do
  @moduledoc """
  DNSimple domain-push API functionality.

  ## Example

      ReqDnsimple.DomainPush.accept(req, 2020, 1, contact_id: 11)
      #=> :ok
  """

  # https://developer.dnsimple.com/v2/domains/pushes/#acceptPush

  @path_schema [
    account_id: [type: :integer, required: true],
    push_id: [type: :integer, required: true]
  ]

  @accept_schema [
    contact_id: [type: :integer, required: true]
  ]

  @doc """
  Accepts one pending domain push using a contact from the target account.

  This sends exactly one request. Contact creation, domain retrieval, and
  ownership checks remain server-side responsibilities.
  """
  @spec accept(Req.Request.t(), ReqDnsimple.account_id(), integer(), keyword()) ::
          :ok | {:error, term()}
  def accept(req, account_id, push_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, push_id: push_id],
             @path_schema
           ),
         {:ok, validated_attrs} <- validate_attrs(attrs) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/pushes/:push_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, push_id: push_id],
          json: Map.new(validated_attrs)
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

  defp validate_attrs(attrs) when is_list(attrs) do
    NimbleOptions.validate(attrs, @accept_schema)
  end

  defp validate_attrs(attrs) do
    {:error,
     %NimbleOptions.ValidationError{
       message: "expected a keyword list",
       value: attrs
     }}
  end
end
