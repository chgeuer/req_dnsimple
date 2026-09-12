defmodule ReqDnsimple.DelegationSignerRecord do
  @moduledoc """
  Operations for domain delegation-signer records.

  Retrieve one delegation-signer record:

      {:ok, delegation_signer_record} =
        ReqDnsimple.DelegationSignerRecord.get(
          client,
          1010,
          "example.test",
          1
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

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error
end
