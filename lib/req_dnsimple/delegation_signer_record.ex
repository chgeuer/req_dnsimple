defmodule ReqDnsimple.DelegationSignerRecord do
  @moduledoc """
  Operations for domain delegation-signer records.

  Create a delegation-signer record from DS data:

      {:ok, delegation_signer_record} =
        ReqDnsimple.DelegationSignerRecord.create(
          client,
          1010,
          "example.test",
          algorithm: "13",
          digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
          digest_type: "2",
          keytag: "12345"
        )

  Retrieve one delegation-signer record:

      {:ok, delegation_signer_record} =
        ReqDnsimple.DelegationSignerRecord.get(
          client,
          1010,
          "example.test",
          1
        )

  List one page or explicitly enumerate every delegation-signer record:

      {:ok, {delegation_signer_records, pagination}} =
        ReqDnsimple.DelegationSignerRecord.list_page(
          client,
          1010,
          "example.test",
          sort: [id: :asc, created_at: :desc],
          page: 2,
          per_page: 30
        )

      {:ok, all_delegation_signer_records} =
        ReqDnsimple.DelegationSignerRecord.list_all(
          client,
          1010,
          "example.test",
          sort: [created_at: :desc]
        )

  Delete one delegation-signer record:

      :ok =
        ReqDnsimple.DelegationSignerRecord.delete(
          client,
          1010,
          "example.test",
          1
        )

  Deletion removes only the selected registry delegation-signer record. It does
  not disable DNSSEC or delete hosted-zone records.
  """

  @type t :: %__MODULE__{
          id: integer(),
          domain_id: integer(),
          algorithm: binary(),
          digest: binary() | nil,
          digest_type: binary() | nil,
          keytag: binary() | nil,
          public_key: binary() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id domain_id algorithm digest digest_type keytag public_key created_at updated_at)a

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    ds_record_id: [type: :integer, required: true]
  ]

  @create_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @create_schema [
    algorithm: [type: :string, required: true],
    digest: [type: :string],
    digest_type: [type: :string],
    keytag: [type: :string],
    public_key: [type: :string]
  ]

  @list_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :created_at]]},
      doc: "Sort by id or created_at. Format: [id: :asc, created_at: :desc]"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of delegation-signer records per page"]
  ]

  @doc """
  Creates a delegation-signer record for a domain.

  Supply `algorithm` and either the complete `digest`, `digest_type`, and
  `keytag` DS tuple or `public_key` KEY data. The values remain strings and are
  sent in one request; this function does not fetch TLD requirements, generate
  keys, or enable DNSSEC.

  ## Example

      ReqDnsimple.DelegationSignerRecord.create(
        req,
        1010,
        "example.test",
        algorithm: "13",
        public_key: "ZmFrZS1vZmZsaW5lLXB1YmxpYy1rZXk="
      )
      #=> {:ok, %ReqDnsimple.DelegationSignerRecord{}}
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def create(req, account_id, domain, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @create_path_schema
           ),
         {:ok, validated_attrs} <- validate_create_attrs(attrs) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/domains/:domain/ds_records",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, delegation_signer_record} -> {:ok, delegation_signer_record}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Lists one page of delegation-signer records for a domain.

  Supports ordered `:sort` terms for `:id` and `:created_at`, plus `:page`
  and `:per_page`. The returned pagination metadata retains its string keys.

  ## Example

      ReqDnsimple.DelegationSignerRecord.list_page(
        req,
        1010,
        "example.test",
        sort: [id: :asc, created_at: :desc],
        page: 2,
        per_page: 30
      )
      #=> {:ok, {[%ReqDnsimple.DelegationSignerRecord{}], %{"current_page" => 2}}}
  """
  @spec list_page(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page(req, account_id, domain, opts \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @create_path_schema
           ),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema) do
      case request_list(req, account_id, domain, validated_opts) do
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => data, "pagination" => pagination}
         } = response} ->
          case decode_page(data, pagination) do
            {:ok, result} -> {:ok, result}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Lists one page of delegation-signer records for a domain.

  This is a convenience alias for `list_page/4`; it never enumerates additional
  pages implicitly.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list(req, account_id, domain, opts \\ []), do: list_page(req, account_id, domain, opts)

  @doc """
  Enumerates every page of delegation-signer records in server order.

  Enumeration always begins at page one, so an explicit `:page` option is
  rejected. Sorting and `:per_page` are retained for every request.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def list_all(req, account_id, domain, opts \\ []) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, domain, &1))
  end

  @doc """
  Retrieves one delegation-signer record from a domain.

  Both DS-data records and KEY-data records are returned as typed structs. Proof
  fields that are unused for the record's representation remain `nil`.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, domain, ds_record_id) do
    with {:ok, _validated_params} <-
           validate_path(account_id, domain, ds_record_id) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain/ds_records/:ds_record_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            ds_record_id: ds_record_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, delegation_signer_record} -> {:ok, delegation_signer_record}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Deletes one delegation-signer record from a domain.

  Returns `:ok` for the API's empty HTTP 204 response. Registry refusals,
  missing records, other HTTP responses, and transport failures are returned
  as explicit error tuples.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, domain, ds_record_id) do
    with {:ok, _validated_params} <-
           validate_path(account_id, domain, ds_record_id) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain/ds_records/:ds_record_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            ds_record_id: ds_record_id
          ]
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

  defp validate_path(account_id, domain, ds_record_id) do
    NimbleOptions.validate(
      [
        account_id: account_id,
        domain: domain,
        ds_record_id: ds_record_id
      ],
      @path_schema
    )
  end

  defp validate_create_attrs(attrs) do
    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema),
         :ok <- validate_proof(validated_attrs) do
      {:ok, validated_attrs}
    end
  end

  defp validate_proof(attrs) do
    has_ds_data =
      Enum.all?([:digest, :digest_type, :keytag], &Keyword.has_key?(attrs, &1))

    if has_ds_data or Keyword.has_key?(attrs, :public_key) do
      :ok
    else
      {:error,
       %NimbleOptions.ValidationError{
         message: "expected a complete DS tuple or :public_key",
         value: attrs
       }}
    end
  end

  defp decode(%{
         "id" => id,
         "domain_id" => domain_id,
         "algorithm" => algorithm,
         "digest" => digest,
         "digest_type" => digest_type,
         "keytag" => keytag,
         "public_key" => public_key,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(domain_id) and is_binary(algorithm) and
              (is_binary(digest) or is_nil(digest)) and
              (is_binary(digest_type) or is_nil(digest_type)) and
              (is_binary(keytag) or is_nil(keytag)) and
              (is_binary(public_key) or is_nil(public_key)) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         domain_id: domain_id,
         algorithm: algorithm,
         digest: digest,
         digest_type: digest_type,
         keytag: keytag,
         public_key: public_key,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp decode_page(data, pagination) when is_list(data) do
    with {:ok, delegation_signer_records} <- decode_many(data),
         true <- valid_pagination?(pagination) do
      {:ok, {delegation_signer_records, pagination}}
    else
      _error -> :error
    end
  end

  defp decode_page(_data, _pagination), do: :error

  defp decode_many(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, delegation_signer_records} ->
      case decode(item) do
        {:ok, delegation_signer_record} ->
          {:cont, {:ok, [delegation_signer_record | delegation_signer_records]}}

        :error ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, delegation_signer_records} ->
        {:ok, Enum.reverse(delegation_signer_records)}

      :error ->
        :error
    end
  end

  defp valid_pagination?(%{
         "current_page" => current_page,
         "per_page" => per_page,
         "total_entries" => total_entries,
         "total_pages" => total_pages
       })
       when is_integer(current_page) and current_page >= 0 and is_integer(per_page) and
              per_page > 0 and is_integer(total_entries) and total_entries >= 0 and
              is_integer(total_pages) and total_pages >= 0,
       do: true

  defp valid_pagination?(_pagination), do: false

  defp request_list(req, account_id, domain, opts) do
    params =
      opts
      |> ReqDnsimple.convert_sort_to_string()
      |> Map.new()

    req
    |> Req.merge(
      method: :get,
      url: "/:account_id/domains/:domain/ds_records",
      path_params_style: :colon,
      path_params: [account_id: account_id, domain: domain],
      params: params
    )
    |> Req.request()
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error
end
