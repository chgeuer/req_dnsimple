defmodule ReqDnsimple.Contact do
  @moduledoc """
  DNSimple Contact API functionality.
  Provides contact management operations.
  """

  # https://developer.dnsimple.com/v2/contacts/

  @type t :: %__MODULE__{
          id: ReqDnsimple.contact_id(),
          account_id: ReqDnsimple.account_id(),
          first_name: binary(),
          last_name: binary(),
          job_title: binary(),
          label: binary(),
          email: binary(),
          fax: binary(),
          phone: binary(),
          address1: binary(),
          address2: binary(),
          postal_code: binary(),
          city: binary(),
          country: binary(),
          state_province: binary(),
          organization_name: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id account_id first_name last_name
               job_title organization_name
               label email fax phone
               address1 address2 postal_code city country state_province
               created_at updated_at)a

  @spec from_json(map()) :: t()
  defp from_json(json) do
    ReqDnsimple.from_json(json, __MODULE__,
      regular: ~w[id account_id first_name last_name
           job_title organization_name
           label email fax phone
           address1 address2 postal_code city country state_province],
      datetime: ~w[created_at updated_at]
    )
  end

  @spec get(Req.Request.t(), ReqDnsimple.account_id(), ReqDnsimple.contact_id()) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  def get(req, account_id, contact_id) do
    # https://developer.dnsimple.com/v2/contacts/#getContact

    req =
      Req.merge(req,
        method: :get,
        url: "/:account_id/contacts/:contact_id",
        path_params_style: :colon,
        path_params: [
          account_id: account_id,
          contact_id: contact_id
        ]
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, from_json(data)}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        {:error, e}
    end
  end

  @list_contacts_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :label, :email]]},
      doc: "Sort by field (id, label, email). Format: [label: :desc] or [:id, email: :asc]"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: :pos_integer, doc: "Number of records per page"]
  ]

  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, [__MODULE__.t()]} | {:error, term()}
  def list(req, account_id, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @list_contacts_schema) do
      params =
        validated_opts
        |> ReqDnsimple.convert_sort_to_string()
        |> Map.new()

      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/contacts",
          path_params_style: :colon,
          path_params: [
            account_id: account_id
          ],
          params: params
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
          {:ok, data |> Enum.map(&from_json/1)}

        {:ok, %Req.Response{status: 404}} ->
          {:error, :not_found}

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, e} ->
          {:error, e}
      end
    end
  end
end
