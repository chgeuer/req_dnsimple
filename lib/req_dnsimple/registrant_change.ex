defmodule ReqDnsimple.RegistrantChange do
  @moduledoc """
  Retrieves registrar contact-change requests.

  ## Example

      ReqDnsimple.RegistrantChange.get(req, 1010, 1)
      #=> {:ok, %ReqDnsimple.RegistrantChange{}}
  """

  @type state :: String.t()

  @type t :: %__MODULE__{
          id: integer(),
          account_id: integer(),
          contact_id: integer(),
          domain_id: integer(),
          state: state(),
          extended_attributes: %{String.t() => String.t()},
          registry_owner_change: boolean(),
          irt_lock_lifted_by: Date.t() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :account_id,
    :contact_id,
    :domain_id,
    :state,
    :extended_attributes,
    :registry_owner_change,
    :irt_lock_lifted_by,
    :created_at,
    :updated_at
  ]

  @path_schema [
    account_id: [type: :integer, required: true],
    registrant_change_id: [type: :integer, required: true]
  ]

  @states ~w(new pending cancelling cancelled completed)

  @doc """
  Retrieves a registrar contact-change request.

  Returns its current state and registry requirements in a typed struct. The
  registry lock-lift date is `nil` until supplied by DNSimple. This function
  sends one bodyless request and performs no requirements check or mutation.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, registrant_change_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               registrant_change_id: registrant_change_id
             ],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/registrar/registrant_changes/:registrant_change_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            registrant_change_id: registrant_change_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, registrant_change} -> {:ok, registrant_change}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp decode(%{
         "id" => id,
         "account_id" => account_id,
         "contact_id" => contact_id,
         "domain_id" => domain_id,
         "state" => state,
         "extended_attributes" => extended_attributes,
         "registry_owner_change" => registry_owner_change,
         "irt_lock_lifted_by" => irt_lock_lifted_by,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(account_id) and is_integer(contact_id) and
              is_integer(domain_id) and state in @states and is_map(extended_attributes) and
              is_boolean(registry_owner_change) do
    with true <-
           Enum.all?(extended_attributes, fn {key, value} ->
             is_binary(key) and is_binary(value)
           end),
         {:ok, irt_lock_lifted_by} <- parse_optional_date(irt_lock_lifted_by),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         account_id: account_id,
         contact_id: contact_id,
         domain_id: domain_id,
         state: state,
         extended_attributes: extended_attributes,
         registry_owner_change: registry_owner_change,
         irt_lock_lifted_by: irt_lock_lifted_by,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp parse_optional_date(nil), do: {:ok, nil}

  defp parse_optional_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp parse_optional_date(_value), do: :error

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error
end
