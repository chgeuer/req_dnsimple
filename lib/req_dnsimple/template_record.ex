defmodule ReqDnsimple.TemplateRecord do
  @moduledoc """
  Operations for records in DNS templates.

  Delete one template record:

      :ok =
        ReqDnsimple.TemplateRecord.delete(
          client,
          1010,
          "offline-template",
          1
        )

  Deletion removes only the selected record from the template. It does not
  remove the template or records previously applied to domains.
  """

  @path_schema [
    account_id: [type: :integer, required: true],
    template: [type: {:or, [:string, :integer]}, required: true],
    record_id: [type: :integer, required: true]
  ]

  @doc """
  Deletes one record from a DNS template.

  The template may be a short name or integer ID. This sends exactly one
  bodyless request and returns `:ok` only for HTTP 204.
  """
  @spec delete(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) :: :ok | {:error, term()}
  def delete(req, account_id, template, record_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template, record_id: record_id],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/templates/:template/records/:record_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            template: template,
            record_id: record_id
          ],
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
