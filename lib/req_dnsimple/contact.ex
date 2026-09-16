defmodule ReqDnsimple.Contact do
  @moduledoc """
  DNSimple Contact API functionality.
  Provides contact management operations.

  HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}` or
  `{:error, %ReqDnsimple.Error{}}`. HTTP 204 successes have `nil` data.
  Errors preserve their original reason in `error.reason`. When no response
  has been received, `error.metadata` is `nil`.
  Collection pagination is nested in `metadata.pagination`. Complete
  enumeration retains ordered page metadata in `metadata.pages` and the
  latest rate-limit budget at the top level.

  ## Example

      ReqDnsimple.Contact.create(req, 1010,
        first_name: "Test",
        last_name: "Contact",
        email: "contact@example.test",
        phone: "+12025550123",
        address1: "1 Example Street",
        city: "Roma",
        state_province: "RM",
        postal_code: "00100",
        country: "IT"
      )
      #=> {:ok, {%ReqDnsimple.Contact{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Contact.update(req, 1010, 1,
        label: "",
        address2: nil,
        fax: nil
      )
      #=> {:ok, {%ReqDnsimple.Contact{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Contact.delete(req, 1010, 1)
      #=> {:ok, {nil, %ReqDnsimple.Metadata{}}}
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
          fax: binary() | nil,
          phone: binary(),
          address1: binary(),
          address2: binary() | nil,
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

  @delete_contact_schema [
    account_id: [type: :integer, required: true],
    contact_id: [type: :integer, required: true]
  ]

  @create_path_schema [
    account_id: [type: :integer, required: true]
  ]

  @create_schema [
    first_name: [type: :string, required: true],
    last_name: [type: :string, required: true],
    address1: [type: :string, required: true],
    address2: [type: {:custom, __MODULE__, :validate_nullable_string, []}],
    city: [type: :string, required: true],
    state_province: [type: :string, required: true],
    postal_code: [type: :string, required: true],
    country: [type: {:custom, __MODULE__, :validate_country, []}, required: true],
    email: [type: :string, required: true],
    phone: [type: :string, required: true],
    fax: [type: {:custom, __MODULE__, :validate_nullable_string, []}],
    label: [type: :string],
    organization_name: [type: :string],
    job_title: [type: :string]
  ]

  @update_schema [
    first_name: [type: :string],
    last_name: [type: :string],
    address1: [type: :string],
    address2: [type: {:custom, __MODULE__, :validate_nullable_string, []}],
    city: [type: :string],
    state_province: [type: :string],
    postal_code: [type: :string],
    country: [type: {:custom, __MODULE__, :validate_country, []}],
    email: [type: :string],
    phone: [type: :string],
    fax: [type: {:custom, __MODULE__, :validate_nullable_string, []}],
    label: [type: :string],
    organization_name: [type: :string],
    job_title: [type: :string]
  ]

  @doc """
  Uses the client's configured account. See `create/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec create(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result(t())
  def create(req, attrs) do
    ReqDnsimple.Client.with_account(req, &create(req, &1, attrs))
  end

  @doc """
  Creates a reusable registrant contact.

  All required contact details are sent in one POST request. Optional fields
  remain omitted unless supplied; `:address2` and `:fax` also accept explicit
  `nil`. Supplying `:organization_name` requires `:job_title`. `:country` must
  contain exactly two uppercase ASCII letters.

  ## Example

      ReqDnsimple.Contact.create(req, 1010,
        first_name: "Test",
        last_name: "Contact",
        email: "contact@example.test",
        phone: "+12025550123",
        address1: "1 Example Street",
        city: "Roma",
        state_province: "RM",
        postal_code: "00100",
        country: "IT"
      )
      #=> {:ok, {%ReqDnsimple.Contact{}, %ReqDnsimple.Metadata{}}}
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result(t())
  def create(req, account_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_attrs} <- validate_create_attrs(attrs) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/contacts",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          json: Map.new(validated_attrs),
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, contact} -> ReqDnsimple.Response.ok(contact, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account. See `update/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec update(
          Req.Request.t(),
          ReqDnsimple.contact_id(),
          keyword()
        ) :: ReqDnsimple.Response.result(t())
  def update(req, contact_id, attrs) do
    ReqDnsimple.Client.with_account(req, &update(req, &1, contact_id, attrs))
  end

  @doc """
  Updates the supplied fields of an existing contact.

  All attributes are optional and omitted attributes are not sent. `:address2`
  and `:fax` accept explicit `nil`, and supplying `:organization_name` requires
  `:job_title`. When supplied, `:country` must contain exactly two uppercase
  ASCII letters. This sends exactly one PATCH request without first retrieving
  the contact.

  ## Example

      ReqDnsimple.Contact.update(req, 1010, 1,
        label: "",
        address2: nil,
        fax: nil
      )
      #=> {:ok, {%ReqDnsimple.Contact{}, %ReqDnsimple.Metadata{}}}
  """
  @spec update(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          ReqDnsimple.contact_id(),
          keyword()
        ) :: ReqDnsimple.Response.result(t())
  def update(req, account_id, contact_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, contact_id: contact_id],
             @delete_contact_schema
           ),
         {:ok, validated_attrs} <- validate_update_attrs(attrs) do
      req =
        Req.merge(req,
          method: :patch,
          url: "/:account_id/contacts/:contact_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            contact_id: contact_id
          ],
          json: Map.new(validated_attrs),
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, contact} -> ReqDnsimple.Response.ok(contact, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc false
  def validate_country(country) when is_binary(country) do
    if Regex.match?(~r/\A[A-Z]{2}\z/, country),
      do: {:ok, country},
      else: {:error, "expected an uppercase ISO 3166-1 alpha-2 country code"}
  end

  def validate_country(_country),
    do: {:error, "expected an uppercase ISO 3166-1 alpha-2 country code"}

  @doc false
  def validate_nullable_string(value) when is_binary(value) or is_nil(value), do: {:ok, value}
  def validate_nullable_string(_value), do: {:error, "expected a string or nil"}

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

  @doc """
  Uses the client's configured account. See `get/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec get(Req.Request.t(), ReqDnsimple.contact_id()) ::
          ReqDnsimple.Response.result(t())
  def get(req, contact_id) do
    ReqDnsimple.Client.with_account(req, &get(req, &1, contact_id))
  end

  @doc """
  Fetches one contact as `{:ok, {contact, metadata}}`.

  HTTP 404 returns a `ReqDnsimple.Error` with `reason: :not_found` and the
  actual response metadata.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), ReqDnsimple.contact_id()) ::
          ReqDnsimple.Response.result(t())
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
      {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
        ReqDnsimple.Response.ok(from_json(data), response)

      {:ok, %Req.Response{status: 404} = response} ->
        ReqDnsimple.Response.error(:not_found, response)

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        {:error, e}
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account. See `delete/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.contact_id()) ::
          ReqDnsimple.Response.result(nil)
  def delete(req, contact_id) do
    ReqDnsimple.Client.with_account(req, &delete(req, &1, contact_id))
  end

  @doc """
  Deletes one contact.

  HTTP 204 returns `{:ok, {nil, metadata}}`.
  Contacts that are in use remain unchanged and return the API's HTTP error.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), ReqDnsimple.contact_id()) ::
          ReqDnsimple.Response.result(nil)
  def delete(req, account_id, contact_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, contact_id: contact_id],
             @delete_contact_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/contacts/:contact_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            contact_id: contact_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 204} = response} ->
          ReqDnsimple.Response.ok(nil, response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @list_contacts_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :label, :email]]},
      doc: "Sort by field (id, label, email). Format: [label: :desc] or [:id, email: :asc]"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: :pos_integer, doc: "Number of records per page"]
  ]

  @doc """
  Uses the client's configured account with default options.
  See `list/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list(Req.Request.t()) ::
          ReqDnsimple.Response.result([t()])
  def list(req) do
    list(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  @spec list(Req.Request.t(), ReqDnsimple.account_id()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list(req, account_id, [])
  end

  def list(req, opts) do
    ReqDnsimple.Client.with_account(req, &list(req, &1, opts))
  end

  @doc """
  Alias for `list_page/3`, including its `{:ok, {contacts, metadata}}` result.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id, opts) do
    list_page(req, account_id, opts)
  end

  @doc """
  Uses the client's configured account with default options.
  See `list_page/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_page(Req.Request.t()) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req) do
    list_page(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_page/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_page(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id()) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_page(req, account_id, [])
  end

  def list_page(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_page(req, &1, opts))
  end

  @doc """
  Lists one page of contacts as `{:ok, {contacts, metadata}}`.

  Supports optional `:sort`, `:page`, and `:per_page` values. Pagination is
  nested in `metadata.pagination` and retains its string keys. HTTP 404
  returns a `ReqDnsimple.Error` with `reason: :not_found` and response metadata.
  """
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req, account_id, opts) do
    with {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_contacts_schema) do
      case request_list(req, account_id, validated_opts) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          ReqDnsimple.Response.ok(Enum.map(data, &from_json/1), response)

        {:ok, %Req.Response{status: 404} = response} ->
          ReqDnsimple.Response.error(:not_found, response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, e} ->
          {:error, e}
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account with default options.
  See `list_all/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_all(Req.Request.t()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req) do
    list_all(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_all/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_all(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_all(req, account_id, [])
  end

  def list_all(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_all(req, &1, opts))
  end

  @doc """
  Enumerates every page of contacts as `{:ok, {contacts, metadata}}`.

  Enumeration begins at page one and rejects an explicit `:page` option.
  Sorting and `:per_page` are retained for every request.

  Metadata retains all responses in `metadata.pages`, in order, and the
  latest rate-limit budget. Aggregate `status`, `pagination`, `request_id`,
  and `etag` are `nil`. A later failure retains completed page metadata in
  `error.metadata.pages`.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
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
      url: "/:account_id/contacts",
      path_params_style: :colon,
      path_params: [account_id: account_id],
      params: params
    )
    |> Req.request()
  end

  defp validate_create_attrs(attrs) do
    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema),
         :ok <- validate_organization(validated_attrs) do
      {:ok, validated_attrs}
    end
  end

  defp validate_update_attrs(attrs) do
    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @update_schema),
         :ok <- validate_organization(validated_attrs) do
      {:ok, validated_attrs}
    end
  end

  defp validate_organization(attrs) do
    if Keyword.has_key?(attrs, :organization_name) and
         not Keyword.has_key?(attrs, :job_title) do
      {:error,
       %NimbleOptions.ValidationError{
         message: "expected :job_title when :organization_name is supplied",
         key: :job_title,
         value: nil
       }}
    else
      :ok
    end
  end

  defp decode(%{
         "id" => id,
         "account_id" => account_id,
         "label" => label,
         "first_name" => first_name,
         "last_name" => last_name,
         "organization_name" => organization_name,
         "job_title" => job_title,
         "address1" => address1,
         "address2" => address2,
         "city" => city,
         "state_province" => state_province,
         "postal_code" => postal_code,
         "country" => country,
         "phone" => phone,
         "fax" => fax,
         "email" => email,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(account_id) and is_binary(label) and
              is_binary(first_name) and is_binary(last_name) and
              is_binary(organization_name) and is_binary(job_title) and
              is_binary(address1) and (is_binary(address2) or is_nil(address2)) and
              is_binary(city) and is_binary(state_province) and is_binary(postal_code) and
              is_binary(country) and is_binary(phone) and (is_binary(fax) or is_nil(fax)) and
              is_binary(email) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         account_id: account_id,
         label: label,
         first_name: first_name,
         last_name: last_name,
         organization_name: organization_name,
         job_title: job_title,
         address1: address1,
         address2: address2,
         city: city,
         state_province: state_province,
         postal_code: postal_code,
         country: country,
         phone: phone,
         fax: fax,
         email: email,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error
end
