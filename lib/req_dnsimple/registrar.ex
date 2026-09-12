defmodule ReqDnsimple.Registrar do
  @moduledoc """
  DNSimple registrar API functionality.

  ## Example

      ReqDnsimple.Registrar.check(req, 1010, "example.test")
      #=> {:ok, %ReqDnsimple.Registrar.CheckResult{}}

      ReqDnsimple.Registrar.authorize_transfer_out(req, 1010, "example.test")
      #=> :ok

      ReqDnsimple.Registrar.disable_auto_renewal(req, 1010, "example.test")
      #=> :ok

      ReqDnsimple.Registrar.enable_auto_renewal(req, 1010, "example.test")
      #=> :ok

      ReqDnsimple.Registrar.renew(req, 1010, "example.test",
        period: 2,
        premium_price: "20.00"
      )
      #=> {:ok, %ReqDnsimple.Registrar.Renewal{}}

      ReqDnsimple.Registrar.restore(req, 1010, "example.test",
        premium_price: "109.00"
      )
      #=> {:ok, %ReqDnsimple.Registrar.Restore{}}

      ReqDnsimple.Registrar.change_delegation(req, 1010, "example.test",
        name_servers: ["ns1.example.test", "ns2.example.test"]
      )
      #=> {:ok, ["ns1.example.test", "ns2.example.test"]}
  """

  defmodule CheckResult do
    @moduledoc """
    The availability information returned by a registrar domain check.
    """

    @type t :: %__MODULE__{
            domain: String.t(),
            available: boolean(),
            premium: boolean(),
            trustee: boolean() | nil
          }

    defstruct [:domain, :available, :premium, :trustee]
  end

  defmodule Renewal do
    @moduledoc """
    A domain-renewal job returned by the registrar API.
    """

    @type state :: String.t()

    @type t :: %__MODULE__{
            id: integer(),
            domain_id: integer(),
            period: 1..9,
            state: state(),
            created_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    defstruct [:id, :domain_id, :period, :state, :created_at, :updated_at]
  end

  defmodule Restore do
    @moduledoc """
    A domain-restore job returned by the registrar API.
    """

    @type state :: String.t()

    @type t :: %__MODULE__{
            id: integer(),
            domain_id: integer(),
            state: state(),
            created_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    defstruct [:id, :domain_id, :state, :created_at, :updated_at]
  end

  # https://developer.dnsimple.com/v2/registrar/#checkDomain
  # https://developer.dnsimple.com/v2/registrar/#authorizeDomainTransferOut
  # https://developer.dnsimple.com/v2/registrar/auto-renewal/#disableDomainAutoRenewal
  # https://developer.dnsimple.com/v2/registrar/auto-renewal/#enableDomainAutoRenewal
  # https://developer.dnsimple.com/v2/registrar/#renewDomain
  # https://developer.dnsimple.com/v2/registrar/#restoreDomain

  @path_schema [
    account_id: [type: :integer, required: true],
    domain_name: [type: :string, required: true]
  ]

  @delegation_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @delegation_schema [
    name_servers: [type: {:list, :string}, required: true]
  ]

  @renewal_schema [
    period: [type: :integer],
    premium_price: [type: :string]
  ]

  @restore_schema [
    premium_price: [type: :string]
  ]

  @doc """
  Checks whether a domain name is available for registration.

  This low-volume endpoint has a stricter rate limit than most DNSimple API
  operations. It sends exactly one request and does not use the paid Domain
  Research API, register an available domain, or retry rate-limit responses.

  Returns the availability, premium status, and optional trustee flag in a
  `CheckResult`. Older successful responses that omit `trustee` return it as
  `nil`.
  """
  @spec check(Req.Request.t(), ReqDnsimple.account_id(), String.t()) ::
          {:ok, CheckResult.t()} | {:error, term()}
  def check(req, account_id, domain_name) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain_name: domain_name],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/registrar/domains/:domain_name/check",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain_name: domain_name],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_check_result(data) do
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
  Authorizes a domain transfer out.

  DNSimple unlocks the domain and emails the authorization code to the
  administrative contact. This function sends exactly one request; it does not
  retrieve the code, contact, or domain, or initiate a transfer.

  Returns `:ok` only for the API's empty HTTP 204 response. Other HTTP responses
  and transport failures are returned as explicit error tuples.
  """
  @spec authorize_transfer_out(Req.Request.t(), ReqDnsimple.account_id(), String.t()) ::
          :ok | {:error, term()}
  def authorize_transfer_out(req, account_id, domain_name) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain_name: domain_name],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/registrar/domains/:domain_name/authorize_transfer_out",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain_name: domain_name]
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
  Disables automatic renewal for a domain.

  This function sends exactly one bodyless request. It does not renew, delete,
  or otherwise modify the domain.

  Returns `:ok` only for the API's empty HTTP 204 response. Registry or TLD
  refusal responses, other HTTP responses, validation failures, and transport
  failures are returned as explicit error tuples.
  """
  @spec disable_auto_renewal(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          :ok | {:error, term()}
  def disable_auto_renewal(req, account_id, domain) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/registrar/domains/:domain/auto_renewal",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
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
  Enables automatic renewal for a domain.

  This function sends exactly one bodyless request. It does not renew the
  domain immediately or read its current state first.

  Returns `:ok` only for the API's empty HTTP 204 response. Registry or TLD
  refusal responses, other HTTP responses, validation failures, and transport
  failures are returned as explicit error tuples.
  """
  @spec enable_auto_renewal(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          :ok | {:error, term()}
  def enable_auto_renewal(req, account_id, domain) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/registrar/domains/:domain/auto_renewal",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
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
  Submits a domain renewal.

  The optional `:period` is sent unchanged; when omitted, DNSimple chooses the
  TLD-specific period. Premium domains can include the caller-confirmed
  `:premium_price`, which is preserved as an exact string. Empty attributes send
  no request body.

  Returns a typed `Renewal` for immediate HTTP 201 and asynchronous HTTP 202
  responses without polling. The function sends exactly one request and does
  not look up prices or registration metadata.
  """
  @spec renew(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          String.t(),
          keyword()
        ) ::
          {:ok, Renewal.t()} | {:error, term()}
  def renew(req, account_id, domain_name, attrs \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain_name: domain_name],
             @path_schema
           ),
         {:ok, validated_attrs} <- validate_renewal_attrs(attrs) do
      request_options = [
        method: :post,
        url: "/:account_id/registrar/domains/:domain_name/renewals",
        path_params_style: :colon,
        path_params: [account_id: account_id, domain_name: domain_name],
        retry: false
      ]

      request_options =
        if validated_attrs == [] do
          request_options
        else
          Keyword.put(request_options, :json, Map.new(validated_attrs))
        end

      req = Req.merge(req, request_options)

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: %{"data" => data}} = response}
        when status in [201, 202] ->
          case decode_renewal(data) do
            {:ok, renewal} -> {:ok, renewal}
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
  Submits an expired-domain restore.

  Premium domains can include the caller-confirmed `:premium_price`, which is
  preserved as an exact string. Empty attributes send no request body.

  Returns a typed `Restore` for immediate HTTP 201 and asynchronous HTTP 202
  responses without polling. The function sends exactly one request and does
  not look up prices, retry renewal, or perform payment or eligibility checks.
  Restore charges and eligibility are determined by DNSimple; payment and
  registry refusal responses are returned as explicit errors.
  """
  @spec restore(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          String.t(),
          keyword()
        ) ::
          {:ok, Restore.t()} | {:error, term()}
  def restore(req, account_id, domain_name, attrs \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain_name: domain_name],
             @path_schema
           ),
         {:ok, validated_attrs} <- validate_restore_attrs(attrs) do
      request_options = [
        method: :post,
        url: "/:account_id/registrar/domains/:domain_name/restores",
        path_params_style: :colon,
        path_params: [account_id: account_id, domain_name: domain_name],
        retry: false
      ]

      request_options =
        if validated_attrs == [] do
          request_options
        else
          Keyword.put(request_options, :json, Map.new(validated_attrs))
        end

      req = Req.merge(req, request_options)

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: %{"data" => data}} = response}
        when status in [201, 202] ->
          case decode_restore(data) do
            {:ok, restore} -> {:ok, restore}
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
  Replaces a domain's registrar delegation.

  The required `:name_servers` option is sent as the root JSON array, including
  when it is explicitly empty. This function performs exactly one request and
  does not read, merge, or otherwise change the existing delegation first.

  Returns the ordered name-server list from a successful HTTP 200 response.
  Other HTTP responses, malformed success bodies, validation failures, and
  transport failures are returned as explicit error tuples.
  """
  @spec change_delegation(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) ::
          {:ok, [String.t()]} | {:error, term()}
  def change_delegation(req, account_id, domain, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ),
         {:ok, validated_attrs} <- validate_delegation_attrs(attrs) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/registrar/domains/:domain/delegation",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          json: validated_attrs[:name_servers],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_name_servers(data) do
            {:ok, name_servers} -> {:ok, name_servers}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp validate_delegation_attrs(attrs) when is_list(attrs) do
    NimbleOptions.validate(attrs, @delegation_schema)
  end

  defp validate_delegation_attrs(attrs) do
    {:error,
     %NimbleOptions.ValidationError{
       message: "expected a keyword list",
       value: attrs
     }}
  end

  defp validate_renewal_attrs(attrs) when is_list(attrs) do
    NimbleOptions.validate(attrs, @renewal_schema)
  end

  defp validate_renewal_attrs(attrs) do
    {:error,
     %NimbleOptions.ValidationError{
       message: "expected a keyword list",
       value: attrs
     }}
  end

  defp validate_restore_attrs(attrs) when is_list(attrs) do
    NimbleOptions.validate(attrs, @restore_schema)
  end

  defp validate_restore_attrs(attrs) do
    {:error,
     %NimbleOptions.ValidationError{
       message: "expected a keyword list",
       value: attrs
     }}
  end

  defp decode_renewal(%{
         "id" => id,
         "domain_id" => domain_id,
         "period" => period,
         "state" => state,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(domain_id) and period in 1..9 and
              state in ["cancelled", "new", "renewing", "renewed", "failed"] do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %Renewal{
         id: id,
         domain_id: domain_id,
         period: period,
         state: state,
         created_at: created_at,
         updated_at: updated_at
       }}
    end
  end

  defp decode_renewal(_data), do: :error

  defp decode_restore(%{
         "id" => id,
         "domain_id" => domain_id,
         "state" => state,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(domain_id) and
              state in ["new", "restoring", "restored", "cancelled"] do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %Restore{
         id: id,
         domain_id: domain_id,
         state: state,
         created_at: created_at,
         updated_at: updated_at
       }}
    end
  end

  defp decode_restore(_data), do: :error

  defp decode_name_servers(name_servers) when is_list(name_servers) do
    if Enum.all?(name_servers, &is_binary/1), do: {:ok, name_servers}, else: :error
  end

  defp decode_name_servers(_name_servers), do: :error

  defp decode_check_result(
         %{
           "domain" => domain,
           "available" => available,
           "premium" => premium
         } = data
       )
       when is_binary(domain) and is_boolean(available) and is_boolean(premium) do
    case Map.fetch(data, "trustee") do
      :error ->
        {:ok,
         %CheckResult{
           domain: domain,
           available: available,
           premium: premium,
           trustee: nil
         }}

      {:ok, trustee} when is_boolean(trustee) ->
        {:ok,
         %CheckResult{
           domain: domain,
           available: available,
           premium: premium,
           trustee: trustee
         }}

      {:ok, _trustee} ->
        :error
    end
  end

  defp decode_check_result(_data), do: :error

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error
end
