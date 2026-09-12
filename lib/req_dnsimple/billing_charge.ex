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
            amount: String.t(),
            description: binary(),
            product_id: integer() | nil,
            product_reference: String.t() | nil,
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
          balance_amount: String.t(),
          invoiced_at: DateTime.t(),
          items: [ReqDnsimple.BillingCharge.Item.t()],
          reference: binary(),
          state: binary(),
          total_amount: String.t()
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
      type: {:custom, ReqDnsimple, :validate_sort, [[:invoiced]]},
      doc:
        "Sort by field. Format: [invoiced: :desc] or [:invoiced] (only invoiced field supported)"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: :pos_integer, doc: "Number of records per page"]
  ]

  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, [__MODULE__.t()]} | {:error, term()}
  def list(req, account_id, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @list_billing_charges_schema),
         {:ok, %Req.Response{status: 200, body: %{"data" => data}}} <-
           request_list(req, account_id, validated_opts) do
      {:ok, Enum.map(data, &from_json/1)}
    else
      {:ok, response} -> ReqDnsimple.response_error(response)
      {:error, error} -> {:error, error}
    end
  end

  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, {[__MODULE__.t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page(req, account_id, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @list_billing_charges_schema) do
      case request_list(req, account_id, validated_opts) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data, "pagination" => pagination}}} ->
          {:ok, {Enum.map(data, &from_json/1), pagination}}

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, e} ->
          {:error, e}
      end
    end
  end

  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, [__MODULE__.t()]} | {:error, term()}
  def list_all(req, account_id, opts \\ []) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, &1))
  end

  defp request_list(req, account_id, opts) do
    params =
      opts
      |> ReqDnsimple.convert_sort_to_string()
      |> Map.new()

    req
    |> Req.merge(
      method: :get,
      url: "/:account_id/billing/charges",
      path_params_style: :colon,
      path_params: [account_id: account_id],
      params: params
    )
    |> Req.request()
  end
end
