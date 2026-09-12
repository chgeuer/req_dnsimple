defmodule ReqDnsimple.EmailForward do
  @moduledoc """
  Operations for domain email forwards.

  Retrieve one email forward:

      {:ok, email_forward} =
        ReqDnsimple.EmailForward.get(
          client,
          1010,
          "example.test",
          1
        )

  Delete one email forward:

      :ok =
        ReqDnsimple.EmailForward.delete(
          client,
          1010,
          "example.test",
          1
        )

  Deletion removes only the selected email forward. It does not send mail or
  modify the domain's MX records.
  """

  @type t :: %__MODULE__{
          id: integer(),
          domain_id: integer(),
          alias_email: binary(),
          destination_email: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          active: boolean()
        }

  defstruct ~w(id domain_id alias_email destination_email created_at updated_at active)a

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    email_forward_id: [type: :integer, required: true]
  ]

  @doc """
  Retrieves one email forward from a domain.

  The returned struct keeps the full alias email distinct from the local-part
  `alias_name` accepted by email-forward creation.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, domain, email_forward_id) do
    with {:ok, _validated_params} <-
           validate_path(account_id, domain, email_forward_id) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain/email_forwards/:email_forward_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            email_forward_id: email_forward_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, email_forward} -> {:ok, email_forward}
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
  Deletes one email forward from a domain.

  Returns `:ok` for the API's empty HTTP 204 response. Deletion refusals,
  missing forwards, other HTTP responses, and transport failures are returned
  as explicit error tuples.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, domain, email_forward_id) do
    with {:ok, _validated_params} <-
           validate_path(account_id, domain, email_forward_id) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain/email_forwards/:email_forward_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            email_forward_id: email_forward_id
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

  defp validate_path(account_id, domain, email_forward_id) do
    NimbleOptions.validate(
      [
        account_id: account_id,
        domain: domain,
        email_forward_id: email_forward_id
      ],
      @path_schema
    )
  end

  defp decode(%{
         "id" => id,
         "domain_id" => domain_id,
         "alias_email" => alias_email,
         "destination_email" => destination_email,
         "created_at" => created_at,
         "updated_at" => updated_at,
         "active" => active
       })
       when is_integer(id) and is_integer(domain_id) and is_binary(alias_email) and
              is_binary(destination_email) and is_boolean(active) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         domain_id: domain_id,
         alias_email: alias_email,
         destination_email: destination_email,
         created_at: created_at,
         updated_at: updated_at,
         active: active
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
