defmodule ReqDnsimple.Account do
  @moduledoc """
  DNSimple Account API functionality.
  Provides account listing and management operations.
  """
  @type t :: %__MODULE__{
          id: integer(),
          email: binary(),
          plan_identifier: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id email plan_identifier created_at updated_at)a

  @spec from_json(map()) :: t()
  def from_json(json) do
    ReqDnsimple.from_json(json, __MODULE__,
      regular: ~w[id email plan_identifier],
      datetime: ~w[created_at updated_at]
    )
  end

  @spec list(Req.Request.t()) :: [ReqDnsimple.Account.t()] | {:error, any()}
  def list(req) do
    # https://developer.dnsimple.com/v2/accounts/

    req =
      Req.merge(req,
        method: :get,
        url: "/accounts"
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 200, body: %{"data" => accounts}}} ->
        accounts |> Enum.map(&ReqDnsimple.Account.from_json/1)

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        {:error, e}
    end
  end
end
