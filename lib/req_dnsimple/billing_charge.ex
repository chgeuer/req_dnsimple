defmodule ReqDnsimple.BillingCharge do
  @moduledoc """
  DNSimple Billing Charge API functionality.
  Provides billing charge listing and management operations.
  """

  # https://developer.dnsimple.com/v2/billing-charges/

  alias __MODULE__.Item

  defmodule Item do
    @moduledoc """
    Billing charge item structure.
    """
    @type t :: %__MODULE__{
            amount: number(),
            description: binary(),
            product_id: integer(),
            product_reference: binary(),
            product_type: binary()
          }

    defstruct ~w(amount description product_id product_reference product_type)a

    @spec from_json(map()) :: t()
    def from_json(json) do
      ReqDnsimple.from_json(json, __MODULE__,
        regular: ~w[amount description product_id product_reference product_type],
        datetime: []
      )
    end
  end

  @type t :: %__MODULE__{
          balance_amount: number(),
          invoiced_at: DateTime.t(),
          items: [ReqDnsimple.BillingCharge.Item.t()],
          reference: binary(),
          state: binary(),
          total_amount: number()
        }

  defstruct ~w(balance_amount items reference state total_amount invoiced_at)a

  @spec from_json(map()) :: t()
  defp from_json(json) do
    json
    |> ReqDnsimple.from_json(__MODULE__,
      regular: ~w[balance_amount reference state total_amount items],
      datetime: ~w[invoiced_at]
    )
    |> Map.update(:items, [], fn item ->
      Enum.map(item, &Item.from_json/1)
    end)
  end

  @list_billing_charges_schema [
    start_date: [type: :string, doc: "Filter charges from this start date (YYYY-MM-DD)"],
    end_date: [type: :string, doc: "Filter charges up to this end date (YYYY-MM-DD)"],
    sort: [
      type: :keyword_list,
      doc:
        "Sort by field. Format: [invoiced: :desc] or [:invoiced] (only invoiced field supported)"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: :pos_integer, doc: "Number of records per page"]
  ]

  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, [__MODULE__.t()]} | {:error, NimbleOptions.ValidationError.t()}
  def list(req, account_id, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @list_billing_charges_schema) do
      params =
        validated_opts
        |> ReqDnsimple.convert_sort_to_string()
        |> Map.new()

      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/billing/charges",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          params: params
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
          {:ok, Enum.map(data, &from_json/1)}

        {:error, e} ->
          {:error, e}
      end
    end
  end
end
