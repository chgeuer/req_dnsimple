defmodule ReqDnsimple.Account do
  @moduledoc """
  DNSimple Account API functionality.
  Provides account listing and management operations.

  Account responses may include `name`, as documented in the Accounts API
  examples and official SDK, even though the field is absent from the OpenAPI
  schema. Older responses may omit it.
  """
  @type t :: %__MODULE__{
          id: integer(),
          email: binary(),
          name: binary() | nil,
          plan_identifier: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id email name plan_identifier created_at updated_at)a

  @spec from_json(map()) :: t()
  def from_json(json) do
    ReqDnsimple.from_json(json, __MODULE__,
      regular: ~w[id email name plan_identifier],
      datetime: ~w[created_at updated_at]
    )
  end

  @doc "Lists accessible accounts with HTTP response metadata."
  @spec list(Req.Request.t()) :: ReqDnsimple.Response.result([t()])
  def list(req) do
    # https://developer.dnsimple.com/v2/accounts/

    req =
      Req.merge(req,
        method: :get,
        url: "/accounts"
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 200, body: %{"data" => accounts}} = response} ->
        ReqDnsimple.Response.ok(Enum.map(accounts, &from_json/1), response)

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        ReqDnsimple.Response.error(e)
    end
  end
end
