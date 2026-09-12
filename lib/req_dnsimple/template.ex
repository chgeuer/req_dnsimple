defmodule ReqDnsimple.Template do
  @moduledoc """
  DNS template operations.

  Retrieve an account template by short name or ID:

      {:ok, template} =
        ReqDnsimple.Template.get(
          client,
          1010,
          "offline-template"
        )

  Apply an account template to a domain:

      :ok =
        ReqDnsimple.Template.apply(
          client,
          1010,
          "example.test",
          "offline-template"
        )

  Applying a template sends exactly one request. Record creation and placeholder
  expansion are performed by DNSimple.

  Delete an account template by short name or ID:

      :ok =
        ReqDnsimple.Template.delete(
          client,
          1010,
          "offline-template"
        )
  """

  @type t :: %__MODULE__{
          id: integer(),
          account_id: integer(),
          name: binary(),
          sid: binary(),
          description: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id account_id name sid description created_at updated_at)a

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    template: [type: {:or, [:string, :integer]}, required: true]
  ]

  @template_path_schema Keyword.delete(@path_schema, :domain)

  @doc """
  Retrieves an account template by short name or ID.

  The returned template has typed timestamps. This sends exactly one bodyless
  request to the plural `/templates` endpoint.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, template) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template],
             @template_path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/templates/:template",
          path_params_style: :colon,
          path_params: [account_id: account_id, template: template]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, template} -> {:ok, template}
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
  Applies a template to a domain.

  The domain and template may be a short name or integer ID. This sends exactly
  one bodyless request and returns `:ok` only for HTTP 204.
  """
  @spec apply(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          binary() | integer()
        ) :: :ok | {:error, term()}
  def apply(req, account_id, domain, template) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain, template: template],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/domains/:domain/templates/:template",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain, template: template],
          retry: false
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

  @doc """
  Deletes an account template by short name or ID.

  This sends exactly one bodyless request and returns `:ok` only for HTTP 204.
  Templates already applied to domains are unaffected.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, template) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template],
             @template_path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/templates/:template",
          path_params_style: :colon,
          path_params: [account_id: account_id, template: template],
          retry: false
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

  defp decode(%{
         "id" => id,
         "account_id" => account_id,
         "name" => name,
         "sid" => sid,
         "description" => description,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(account_id) and is_binary(name) and is_binary(sid) and
              is_binary(description) and is_binary(created_at) and is_binary(updated_at) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         account_id: account_id,
         name: name,
         sid: sid,
         description: description,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _ -> :error
    end
  end

  defp decode(_data), do: :error

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end
end
