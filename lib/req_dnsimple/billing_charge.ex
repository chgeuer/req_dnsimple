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

  @doc """
  Uses the client's configured account with default options.
  See `list/3` for operation options and return values.
  Returns a missing-account `ReqDnsimple.Error` without making a request when the client is unscoped.
  """
  @spec list(Req.Request.t()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  def list(req) do
    list(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list/3` for operation options and return values.
  Returns a missing-account `ReqDnsimple.Error` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  @spec list(Req.Request.t(), ReqDnsimple.account_id()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  def list(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list(req, account_id, [])
  end

  def list(req, opts) do
    ReqDnsimple.Client.with_account(req, &list(req, &1, opts))
  end

  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  def list(req, account_id, opts) do
    with {:ok, validated_opts} <-
           ReqDnsimple.validate_options(opts, @list_billing_charges_schema),
         {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} <-
           request_list(req, account_id, validated_opts) do
      ReqDnsimple.Response.ok(Enum.map(data, &from_json/1), response)
    else
      {:ok, response} -> ReqDnsimple.response_error(response)
      {:error, error} -> ReqDnsimple.Response.error(error)
    end
  end

  @doc """
  Uses the client's configured account with default options.
  See `list_page/3` for operation options and return values.
  Returns a missing-account `ReqDnsimple.Error` without making a request when the client is unscoped.
  """
  @spec list_page(Req.Request.t()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  def list_page(req) do
    list_page(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_page/3` for operation options and return values.
  Returns a missing-account `ReqDnsimple.Error` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_page(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  def list_page(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_page(req, account_id, [])
  end

  def list_page(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_page(req, &1, opts))
  end

  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  def list_page(req, account_id, opts) do
    with {:ok, validated_opts} <-
           ReqDnsimple.validate_options(opts, @list_billing_charges_schema) do
      case request_list(req, account_id, validated_opts) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          ReqDnsimple.Response.ok(Enum.map(data, &from_json/1), response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, e} ->
          ReqDnsimple.Response.error(e)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account with default options.
  See `list_all/3` for operation options and return values.
  Returns a missing-account `ReqDnsimple.Error` without making a request when the client is unscoped.
  """
  @spec list_all(Req.Request.t()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  def list_all(req) do
    list_all(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_all/3` for operation options and return values.
  Returns a missing-account `ReqDnsimple.Error` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_all(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  def list_all(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_all(req, account_id, [])
  end

  def list_all(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_all(req, &1, opts))
  end

  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([__MODULE__.t()])
  def list_all(req, account_id, opts) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, &1))
  end

  defp request_list(req, account_id, opts) do
    params =
      opts
      |> ReqDnsimple.convert_sort_to_string()
      |> Map.new()

    req
    |> ReqDnsimple.Helper.merge(
      method: :get,
      url: "/:account_id/billing/charges",
      path_params_style: :colon,
      path_params: [account_id: account_id],
      params: params
    )
    |> Req.request()
  end
end
