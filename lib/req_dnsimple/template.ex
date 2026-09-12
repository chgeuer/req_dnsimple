defmodule ReqDnsimple.Template do
  @moduledoc """
  DNS template operations.

  Apply an account template to a domain:

      :ok =
        ReqDnsimple.Template.apply(
          client,
          1010,
          "example.test",
          "offline-template"
        )

  Applying a template sends exactly one request. Record creation and placeholder
  expansion are performed by DNSimple.

  Delete an account template by short name or ID:

      :ok =
        ReqDnsimple.Template.delete(
          client,
          1010,
          "offline-template"
        )
  """

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    template: [type: {:or, [:string, :integer]}, required: true]
  ]

  @delete_path_schema Keyword.delete(@path_schema, :domain)

  @doc """
  Applies a template to a domain.

  The domain and template may be a short name or integer ID. This sends exactly
  one bodyless request and returns `:ok` only for HTTP 204.
  """
  @spec apply(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          binary() | integer()
        ) :: :ok | {:error, term()}
  def apply(req, account_id, domain, template) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain, template: template],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/domains/:domain/templates/:template",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain, template: template],
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

  @doc """
  Deletes an account template by short name or ID.

  This sends exactly one bodyless request and returns `:ok` only for HTTP 204.
  Templates already applied to domains are unaffected.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, template) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template],
             @delete_path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/templates/:template",
          path_params_style: :colon,
          path_params: [account_id: account_id, template: template],
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
