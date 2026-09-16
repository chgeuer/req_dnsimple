defmodule ReqDnsimple.Registrar do
  @moduledoc """
  DNSimple registrar API functionality.

  HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}`; HTTP 204
  responses use `nil` data. Metadata contains the HTTP status and response
  headers, including rate limits and Retry-After. Header parse failures are
  recorded in `metadata.parse_errors` without discarding valid resource data.

  Failures return `{:error, %ReqDnsimple.Error{}}`. HTTP failures retain response
  metadata; validation, missing-account, and transport failures have `nil`
  metadata. Scoped overloads use the same result contract.

  ## Example

      ReqDnsimple.Registrar.check(req, 1010, "example.test")
      #=> {:ok, {%ReqDnsimple.Registrar.CheckResult{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.get_prices(req, 1010, "example.test")
      #=> {:ok, {%ReqDnsimple.Registrar.Prices{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.get_transfer_lock(req, 1010, "example.test")
      #=> {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: true}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.enable_transfer_lock(req, 1010, "example.test")
      #=> {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: true}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.disable_transfer_lock(req, 1010, "example.test")
      #=> {:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: false}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.authorize_transfer_out(req, 1010, "example.test")
      #=> {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}}

      ReqDnsimple.Registrar.disable_auto_renewal(req, 1010, "example.test")
      #=> {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}}

      ReqDnsimple.Registrar.enable_auto_renewal(req, 1010, "example.test")
      #=> {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}}

      ReqDnsimple.Registrar.enable_whois_privacy(req, 1010, "example.test")
      #=> {:ok, {%ReqDnsimple.Registrar.WhoisPrivacy{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.disable_whois_privacy(req, 1010, "example.test")
      #=> {:ok, {%ReqDnsimple.Registrar.WhoisPrivacy{enabled: false}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.register(req, 1010, "example.test",
        registrant_id: 11,
        whois_privacy: false,
        premium_price: "12.00"
      )
      #=> {:ok, {%ReqDnsimple.Registrar.Registration{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.transfer(req, 1010, "example.test",
        registrant_id: 11,
        auth_code: "fake-transfer-code",
        whois_privacy: false,
        premium_price: "12.00"
      )
      #=> {:ok, {%ReqDnsimple.Registrar.Transfer{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.renew(req, 1010, "example.test",
        period: 2,
        premium_price: "20.00"
      )
      #=> {:ok, {%ReqDnsimple.Registrar.Renewal{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.restore(req, 1010, "example.test",
        premium_price: "109.00"
      )
      #=> {:ok, {%ReqDnsimple.Registrar.Restore{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.get_delegation(req, 1010, "example.test")
      #=> {:ok, {["ns1.example.test", "ns2.example.test"], %ReqDnsimple.Metadata{}}}

      ReqDnsimple.Registrar.change_delegation(req, 1010, "example.test",
        name_servers: ["ns1.example.test", "ns2.example.test"]
      )
      #=> {:ok, {["ns1.example.test", "ns2.example.test"], %ReqDnsimple.Metadata{}}}
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

  defmodule Prices do
    @moduledoc """
    Domain registration and lifecycle prices returned by the registrar API.
    """

    @type t :: %__MODULE__{
            domain: String.t(),
            premium: boolean(),
            registration_price: number(),
            renewal_price: number(),
            transfer_price: number() | nil,
            restore_price: number(),
            trustee_price: number() | nil
          }

    defstruct [
      :domain,
      :premium,
      :registration_price,
      :renewal_price,
      :transfer_price,
      :restore_price,
      :trustee_price
    ]
  end

  defmodule TransferLock do
    @moduledoc """
    The domain transfer-lock state returned by the registrar API.
    """

    @type t :: %__MODULE__{enabled: boolean()}

    defstruct [:enabled]
  end

  defmodule Registration do
    @moduledoc """
    A domain-registration job returned by the registrar API.
    """

    @type state :: String.t()

    @type t :: %__MODULE__{
            id: integer(),
            domain_id: integer(),
            registrant_id: integer(),
            period: 1..10,
            state: state(),
            auto_renew: boolean(),
            whois_privacy: boolean(),
            trustee: boolean(),
            created_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    defstruct [
      :id,
      :domain_id,
      :registrant_id,
      :period,
      :state,
      :auto_renew,
      :whois_privacy,
      :trustee,
      :created_at,
      :updated_at
    ]
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

  defmodule Transfer do
    @moduledoc """
    An inbound domain-transfer job returned by the registrar API.
    """

    @type state :: String.t()

    @type t :: %__MODULE__{
            id: integer(),
            domain_id: integer(),
            registrant_id: integer(),
            state: state(),
            auto_renew: boolean(),
            whois_privacy: boolean(),
            trustee: boolean(),
            status_description: String.t() | nil,
            created_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    defstruct [
      :id,
      :domain_id,
      :registrant_id,
      :state,
      :auto_renew,
      :whois_privacy,
      :trustee,
      :status_description,
      :created_at,
      :updated_at
    ]
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

  defmodule WhoisPrivacy do
    @moduledoc """
    WHOIS privacy state returned by the registrar API.
    """

    @type t :: %__MODULE__{
            id: integer(),
            domain_id: integer(),
            enabled: boolean() | nil,
            expires_on: Date.t() | nil,
            created_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    defstruct [:id, :domain_id, :enabled, :expires_on, :created_at, :updated_at]
  end

  # https://developer.dnsimple.com/v2/registrar/#checkDomain
  # https://developer.dnsimple.com/v2/registrar/#getDomainPrices
  # https://developer.dnsimple.com/v2/registrar/transfer-lock/#getDomainTransferLock
  # https://developer.dnsimple.com/v2/registrar/transfer-lock/#disableDomainTransferLock
  # https://developer.dnsimple.com/v2/registrar/#authorizeDomainTransferOut
  # https://developer.dnsimple.com/v2/registrar/auto-renewal/#disableDomainAutoRenewal
  # https://developer.dnsimple.com/v2/registrar/auto-renewal/#enableDomainAutoRenewal
  # https://developer.dnsimple.com/v2/registrar/whois-privacy/#enableWhoisPrivacy
  # https://developer.dnsimple.com/v2/registrar/whois-privacy/#disableWhoisPrivacy
  # https://developer.dnsimple.com/v2/registrar/#registerDomain
  # https://developer.dnsimple.com/v2/registrar/#transferDomain
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

  @registration_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: :string, required: true],
    registration_id: [type: :integer, required: true]
  ]

  @renewal_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: :string, required: true],
    renewal_id: [type: :integer, required: true]
  ]

  @transfer_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: :string, required: true],
    transfer_id: [type: :integer, required: true]
  ]

  @delegation_schema [
    name_servers: [type: {:list, :string}, required: true]
  ]

  @renewal_schema [
    period: [type: :integer],
    premium_price: [type: :string]
  ]

  @registration_schema [
    registrant_id: [type: :integer, required: true],
    whois_privacy: [type: :boolean],
    auto_renew: [type: :boolean],
    trustee: [type: :boolean],
    extended_attributes: [type: :any],
    premium_price: [type: :string],
    linked_provider: [type: :string]
  ]

  @restore_schema [
    premium_price: [type: :string]
  ]

  @transfer_schema [
    registrant_id: [type: :integer, required: true],
    auth_code: [type: :string],
    whois_privacy: [type: :boolean],
    auto_renew: [type: :boolean],
    trustee: [type: :boolean],
    extended_attributes: [type: :any],
    premium_price: [type: :string]
  ]

  @doc """
  Uses the client's configured account. See `check/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec check(Req.Request.t(), String.t()) ::
          ReqDnsimple.Response.result(CheckResult.t())
  def check(req, domain_name) do
    ReqDnsimple.Client.with_account(req, &check(req, &1, domain_name))
  end

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
          ReqDnsimple.Response.result(CheckResult.t())
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
            {:ok, result} -> ReqDnsimple.Response.ok(result, response)
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
  Uses the client's configured account. See `get_prices/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec get_prices(Req.Request.t(), String.t()) ::
          ReqDnsimple.Response.result(Prices.t())
  def get_prices(req, domain_name) do
    ReqDnsimple.Client.with_account(req, &get_prices(req, &1, domain_name))
  end

  @doc """
  Retrieves registration and lifecycle prices for a domain name.

  Prices are returned as JSON numbers in a `Prices` struct. The transfer and
  trustee prices are optional and are `nil` when DNSimple omits them. This
  function sends exactly one bodyless request and does not register, renew,
  transfer, restore, or otherwise modify the domain.
  """
  @spec get_prices(Req.Request.t(), ReqDnsimple.account_id(), String.t()) ::
          ReqDnsimple.Response.result(Prices.t())
  def get_prices(req, account_id, domain_name) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain_name: domain_name],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/registrar/domains/:domain_name/prices",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain_name: domain_name],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_prices(data) do
            {:ok, prices} -> ReqDnsimple.Response.ok(prices, response)
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
  Uses the client's configured account. See `get_transfer_lock/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec get_transfer_lock(
          Req.Request.t(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(TransferLock.t())
  def get_transfer_lock(req, domain) do
    ReqDnsimple.Client.with_account(req, &get_transfer_lock(req, &1, domain))
  end

  @doc """
  Retrieves a domain's transfer-lock state.

  The domain can be identified by name or integer ID. This function sends
  exactly one bodyless request and does not look up the domain or change its
  transfer-lock state.

  Returns the enabled state as a typed `TransferLock` resource. Other HTTP
  responses, malformed success bodies, validation failures, and transport
  failures are returned as explicit error tuples.
  """
  @spec get_transfer_lock(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(TransferLock.t())
  def get_transfer_lock(req, account_id, domain) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/registrar/domains/:domain/transfer_lock",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_transfer_lock(data) do
            {:ok, transfer_lock} -> ReqDnsimple.Response.ok(transfer_lock, response)
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
  Uses the client's configured account. See `enable_transfer_lock/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec enable_transfer_lock(
          Req.Request.t(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(TransferLock.t())
  def enable_transfer_lock(req, domain) do
    ReqDnsimple.Client.with_account(req, &enable_transfer_lock(req, &1, domain))
  end

  @doc """
  Enables a domain's transfer lock.

  The domain can be identified by name or integer ID. This function sends
  exactly one bodyless request and does not look up the domain or perform any
  other registrar operation.

  Returns the resulting enabled state as a typed `TransferLock` resource.
  Other HTTP responses, malformed success bodies, validation failures, and
  transport failures are returned as explicit error tuples.
  """
  @spec enable_transfer_lock(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(TransferLock.t())
  def enable_transfer_lock(req, account_id, domain) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/registrar/domains/:domain/transfer_lock",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode_transfer_lock(data) do
            {:ok, transfer_lock} -> ReqDnsimple.Response.ok(transfer_lock, response)
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
  Uses the client's configured account. See `disable_transfer_lock/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec disable_transfer_lock(
          Req.Request.t(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(TransferLock.t())
  def disable_transfer_lock(req, domain) do
    ReqDnsimple.Client.with_account(req, &disable_transfer_lock(req, &1, domain))
  end

  @doc """
  Disables a domain's transfer lock.

  The domain can be identified by name or integer ID. This function sends
  exactly one bodyless request and does not retrieve an authorization code or
  initiate a transfer.

  Returns the resulting disabled state as a typed `TransferLock` resource.
  Other HTTP responses, malformed success bodies, validation failures, and
  transport failures are returned as explicit error tuples.
  """
  @spec disable_transfer_lock(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(TransferLock.t())
  def disable_transfer_lock(req, account_id, domain) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/registrar/domains/:domain/transfer_lock",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_transfer_lock(data) do
            {:ok, transfer_lock} -> ReqDnsimple.Response.ok(transfer_lock, response)
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
  Uses the client's configured account. See `authorize_transfer_out/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec authorize_transfer_out(Req.Request.t(), String.t()) ::
          ReqDnsimple.Response.result(nil)
  def authorize_transfer_out(req, domain_name) do
    ReqDnsimple.Client.with_account(req, &authorize_transfer_out(req, &1, domain_name))
  end

  @doc """
  Authorizes a domain transfer out.

  DNSimple unlocks the domain and emails the authorization code to the
  administrative contact. This function sends exactly one request; it does not
  retrieve the code, contact, or domain, or initiate a transfer.

  Returns `{:ok, {nil, %ReqDnsimple.Metadata{status: 204}}}` only for the API's empty HTTP 204 response. Other HTTP responses
  and transport failures are returned as explicit error tuples.
  """
  @spec authorize_transfer_out(Req.Request.t(), ReqDnsimple.account_id(), String.t()) ::
          ReqDnsimple.Response.result(nil)
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

  @doc """
  Uses the client's configured account. See `disable_auto_renewal/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec disable_auto_renewal(
          Req.Request.t(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(nil)
  def disable_auto_renewal(req, domain) do
    ReqDnsimple.Client.with_account(req, &disable_auto_renewal(req, &1, domain))
  end

  @doc """
  Disables automatic renewal for a domain.

  This function sends exactly one bodyless request. It does not renew, delete,
  or otherwise modify the domain.

  Returns `{:ok, {nil, %ReqDnsimple.Metadata{status: 204}}}` only for the API's empty HTTP 204 response. Registry or TLD
  refusal responses, other HTTP responses, validation failures, and transport
  failures are returned as explicit error tuples.
  """
  @spec disable_auto_renewal(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(nil)
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

  @doc """
  Uses the client's configured account. See `enable_auto_renewal/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec enable_auto_renewal(
          Req.Request.t(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(nil)
  def enable_auto_renewal(req, domain) do
    ReqDnsimple.Client.with_account(req, &enable_auto_renewal(req, &1, domain))
  end

  @doc """
  Enables automatic renewal for a domain.

  This function sends exactly one bodyless request. It does not renew the
  domain immediately or read its current state first.

  Returns `{:ok, {nil, %ReqDnsimple.Metadata{status: 204}}}` only for the API's empty HTTP 204 response. Registry or TLD
  refusal responses, other HTTP responses, validation failures, and transport
  failures are returned as explicit error tuples.
  """
  @spec enable_auto_renewal(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(nil)
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

  @doc """
  Uses the client's configured account. See `enable_whois_privacy/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec enable_whois_privacy(
          Req.Request.t(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(WhoisPrivacy.t())
  def enable_whois_privacy(req, domain) do
    ReqDnsimple.Client.with_account(req, &enable_whois_privacy(req, &1, domain))
  end

  @doc """
  Enables WHOIS privacy for a domain.

  This function sends exactly one bodyless request and does not look up the
  domain, check pricing, or perform a separate purchase. Modern responses use
  HTTP 200; legacy enablement can return HTTP 201. Legacy payment failures,
  registry or TLD refusals, other HTTP responses, validation failures, and
  transport failures are returned as explicit error tuples.

  Returns the resulting privacy state as a typed `WhoisPrivacy` resource.
  Newly created privacy records can have `nil` for `enabled` and `expires_on`;
  these values are preserved until DNSimple finishes provisioning the record.
  """
  @spec enable_whois_privacy(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(WhoisPrivacy.t())
  def enable_whois_privacy(req, account_id, domain) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/registrar/domains/:domain/whois_privacy",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: %{"data" => data}} = response}
        when status in [200, 201] ->
          case decode_whois_privacy(data) do
            {:ok, whois_privacy} -> ReqDnsimple.Response.ok(whois_privacy, response)
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
  Uses the client's configured account. See `disable_whois_privacy/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec disable_whois_privacy(
          Req.Request.t(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(WhoisPrivacy.t())
  def disable_whois_privacy(req, domain) do
    ReqDnsimple.Client.with_account(req, &disable_whois_privacy(req, &1, domain))
  end

  @doc """
  Disables WHOIS privacy for a domain.

  This function sends exactly one bodyless DELETE request and does not look up
  the domain, issue a refund, or perform another registrar operation. Registry
  or TLD refusals, other HTTP responses, validation failures, and transport
  failures are returned as explicit error tuples.

  Returns the resulting privacy state as a typed `WhoisPrivacy` resource.
  """
  @spec disable_whois_privacy(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result(WhoisPrivacy.t())
  def disable_whois_privacy(req, account_id, domain) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/registrar/domains/:domain/whois_privacy",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_whois_privacy(data) do
            {:ok, whois_privacy} -> ReqDnsimple.Response.ok(whois_privacy, response)
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
  Uses the client's configured account with default options.
  See `renew/4` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.
  """
  @spec renew(
          Req.Request.t(),
          String.t()
        ) ::
          ReqDnsimple.Response.result(Renewal.t())
  def renew(req, domain_name) do
    renew(req, domain_name, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `renew/4` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec renew(
          Req.Request.t(),
          String.t(),
          keyword()
        ) ::
          ReqDnsimple.Response.result(Renewal.t())
  @spec renew(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          String.t()
        ) ::
          ReqDnsimple.Response.result(Renewal.t())
  def renew(req, account_id, domain_name)
      when is_integer(domain_name) or is_binary(domain_name) do
    renew(req, account_id, domain_name, [])
  end

  def renew(req, domain_name, attrs) do
    ReqDnsimple.Client.with_account(req, &renew(req, &1, domain_name, attrs))
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
          ReqDnsimple.Response.result(Renewal.t())
  def renew(req, account_id, domain_name, attrs) do
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
            {:ok, renewal} -> ReqDnsimple.Response.ok(renewal, response)
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
  Uses the client's configured account. See `register/4` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec register(
          Req.Request.t(),
          String.t(),
          keyword()
        ) ::
          ReqDnsimple.Response.result(Registration.t())
  def register(req, domain_name, attrs) do
    ReqDnsimple.Client.with_account(req, &register(req, &1, domain_name, attrs))
  end

  @doc """
  Submits a domain registration for an existing contact.

  `:registrant_id` is required. Optional settings are `:whois_privacy`,
  `:auto_renew`, `:trustee`, `:extended_attributes`, `:premium_price`, and
  `:linked_provider`. Extended-attribute keys must be strings, and a supplied
  premium price remains an exact string.

  Returns a typed `Registration` for immediate HTTP 201 and asynchronous HTTP
  202 responses without polling. Registration, service, trustee, and premium
  charges are determined by DNSimple. Callers must confirm any premium price
  before invoking this operation. The function sends exactly one request and
  does not check availability or prices, fetch or create contacts, create a
  hosted domain, or perform any other preflight or follow-up operation.
  """
  @spec register(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          String.t(),
          keyword()
        ) ::
          ReqDnsimple.Response.result(Registration.t())
  def register(req, account_id, domain_name, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain_name: domain_name],
             @path_schema
           ),
         {:ok, validated_attrs} <- validate_registration_attrs(attrs) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/registrar/domains/:domain_name/registrations",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain_name: domain_name],
          json: Map.new(validated_attrs),
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: %{"data" => data}} = response}
        when status in [201, 202] ->
          case decode_registration(data) do
            {:ok, registration} -> ReqDnsimple.Response.ok(registration, response)
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
  Uses the client's configured account. See `transfer/4` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec transfer(
          Req.Request.t(),
          String.t(),
          keyword()
        ) ::
          ReqDnsimple.Response.result(Transfer.t())
  def transfer(req, domain_name, attrs) do
    ReqDnsimple.Client.with_account(req, &transfer(req, &1, domain_name, attrs))
  end

  @doc """
  Submits an inbound domain transfer for an existing contact.

  `:registrant_id` is required. Optional settings are `:auth_code`,
  `:whois_privacy`, `:auto_renew`, `:trustee`, `:extended_attributes`, and
  `:premium_price`. Authorization codes and extended attributes are supplied
  only when required by the TLD. Extended-attribute keys must be strings, and
  a supplied premium price remains an exact string.

  Returns a typed `Transfer` for immediate HTTP 201 and asynchronous HTTP 202
  responses without polling. The function sends exactly one request and does
  not fetch TLD metadata, unlock or authorize transfer-out, check prices, or
  perform any other preflight or follow-up operation.
  """
  @spec transfer(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          String.t(),
          keyword()
        ) ::
          ReqDnsimple.Response.result(Transfer.t())
  def transfer(req, account_id, domain_name, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain_name: domain_name],
             @path_schema
           ),
         {:ok, validated_attrs} <- validate_transfer_attrs(attrs) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/registrar/domains/:domain_name/transfers",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain_name: domain_name],
          json: Map.new(validated_attrs),
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: %{"data" => data}} = response}
        when status in [201, 202] ->
          case decode_transfer(data) do
            {:ok, transfer} -> ReqDnsimple.Response.ok(transfer, response)
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
  Uses the client's configured account with default options.
  See `restore/4` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.
  """
  @spec restore(
          Req.Request.t(),
          String.t()
        ) ::
          ReqDnsimple.Response.result(Restore.t())
  def restore(req, domain_name) do
    restore(req, domain_name, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `restore/4` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec restore(
          Req.Request.t(),
          String.t(),
          keyword()
        ) ::
          ReqDnsimple.Response.result(Restore.t())
  @spec restore(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          String.t()
        ) ::
          ReqDnsimple.Response.result(Restore.t())
  def restore(req, account_id, domain_name)
      when is_integer(domain_name) or is_binary(domain_name) do
    restore(req, account_id, domain_name, [])
  end

  def restore(req, domain_name, attrs) do
    ReqDnsimple.Client.with_account(req, &restore(req, &1, domain_name, attrs))
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
          ReqDnsimple.Response.result(Restore.t())
  def restore(req, account_id, domain_name, attrs) do
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
            {:ok, restore} -> ReqDnsimple.Response.ok(restore, response)
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
  Uses the client's configured account. See `get_delegation/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec get_delegation(
          Req.Request.t(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result([String.t()])
  def get_delegation(req, domain) do
    ReqDnsimple.Client.with_account(req, &get_delegation(req, &1, domain))
  end

  @doc """
  Retrieves a domain's registrar delegation.

  The ordered list of name-server hostnames is returned exactly as supplied by
  DNSimple. This is distinct from hosted-zone apex NS records.

  This function sends exactly one bodyless request. Other HTTP responses,
  malformed success bodies, validation failures, and transport failures are
  returned as explicit error tuples.
  """
  @spec get_delegation(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result([String.t()])
  def get_delegation(req, account_id, domain) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/registrar/domains/:domain/delegation",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_name_servers(data) do
            {:ok, name_servers} -> ReqDnsimple.Response.ok(name_servers, response)
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
  Uses the client's configured account. See `change_delegation/4` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec change_delegation(
          Req.Request.t(),
          binary() | integer(),
          keyword()
        ) ::
          ReqDnsimple.Response.result([String.t()])
  def change_delegation(req, domain, attrs) do
    ReqDnsimple.Client.with_account(req, &change_delegation(req, &1, domain, attrs))
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
          ReqDnsimple.Response.result([String.t()])
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
            {:ok, name_servers} -> ReqDnsimple.Response.ok(name_servers, response)
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
  Retrieves a registration using the client's configured account.

  See `get_registration/4` for the domain name, registration ID, and return
  values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` before authentication or HTTP
  when the client has no configured account.
  """
  @spec get_registration(Req.Request.t(), String.t(), integer()) ::
          ReqDnsimple.Response.result(Registration.t())
  def get_registration(req, domain, registration_id) do
    ReqDnsimple.Client.with_account(req, &get_registration(req, &1, domain, registration_id))
  end

  @doc """
  Retrieves an existing domain registration by its domain name and registration ID.

  Sends one bodyless GET request and returns `{:ok, {registration, %ReqDnsimple.Metadata{}}}` with a typed
  `Registration` on HTTP 200, including its current or terminal state. It does
  not register the domain, poll for completion, or perform follow-up requests.
  Validation failures, malformed success bodies, other HTTP responses, and
  transport failures return `{:error, %ReqDnsimple.Error{reason: reason}}`.

  ## Example

      ReqDnsimple.Registrar.get_registration(req, 1010, "example.com", 361)
      #=> {:ok, {%ReqDnsimple.Registrar.Registration{}, %ReqDnsimple.Metadata{}}}
  """
  @spec get_registration(Req.Request.t(), ReqDnsimple.account_id(), String.t(), integer()) ::
          ReqDnsimple.Response.result(Registration.t())
  def get_registration(req, account_id, domain, registration_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain, registration_id: registration_id],
             @registration_path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/registrar/domains/:domain/registrations/:registration_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            registration_id: registration_id
          ],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_registration(data) do
            {:ok, registration} -> ReqDnsimple.Response.ok(registration, response)
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
  Retrieves a renewal using the client's configured account.

  See `get_renewal/4` for the domain name, renewal ID, and return values. Returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` before authentication or HTTP when the client
  has no configured account.
  """
  @spec get_renewal(Req.Request.t(), String.t(), integer()) ::
          ReqDnsimple.Response.result(Renewal.t())
  def get_renewal(req, domain, renewal_id) do
    ReqDnsimple.Client.with_account(req, &get_renewal(req, &1, domain, renewal_id))
  end

  @doc """
  Retrieves an existing domain renewal by its domain name and renewal ID.

  Sends one bodyless GET request and returns `{:ok, {renewal, %ReqDnsimple.Metadata{}}}` with a typed
  `Renewal` on HTTP 200. Legacy HTTP 201 responses are also accepted. The
  renewal's current or terminal state is returned without renewing the domain,
  polling, or making follow-up requests. Validation failures, malformed success
  bodies, other HTTP responses, and transport failures return `{:error, %ReqDnsimple.Error{reason: reason}}`.

  ## Example

      ReqDnsimple.Registrar.get_renewal(req, 1010, "example.com", 1)
      #=> {:ok, {%ReqDnsimple.Registrar.Renewal{}, %ReqDnsimple.Metadata{}}}
  """
  @spec get_renewal(Req.Request.t(), ReqDnsimple.account_id(), String.t(), integer()) ::
          ReqDnsimple.Response.result(Renewal.t())
  def get_renewal(req, account_id, domain, renewal_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain, renewal_id: renewal_id],
             @renewal_path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/registrar/domains/:domain/renewals/:renewal_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain, renewal_id: renewal_id],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: %{"data" => data}} = response}
        when status in [200, 201] ->
          case decode_renewal(data) do
            {:ok, renewal} -> ReqDnsimple.Response.ok(renewal, response)
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
  Retrieves a transfer using the client's configured account.

  See `get_transfer/4` for the domain name, transfer ID, and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` before authentication or HTTP when the
  client has no configured account.
  """
  @spec get_transfer(Req.Request.t(), String.t(), integer()) ::
          ReqDnsimple.Response.result(Transfer.t())
  def get_transfer(req, domain, transfer_id) do
    ReqDnsimple.Client.with_account(req, &get_transfer(req, &1, domain, transfer_id))
  end

  @doc """
  Retrieves an existing domain transfer by its domain name and transfer ID.

  Sends one bodyless GET request and returns `{:ok, {transfer, %ReqDnsimple.Metadata{}}}` with a typed
  `Transfer` on HTTP 200. Current and terminal states, including cancellation
  descriptions, are preserved without starting a transfer or polling.
  Validation failures, malformed success bodies, other HTTP responses, and
  transport failures return `{:error, %ReqDnsimple.Error{reason: reason}}`.

  ## Example

      ReqDnsimple.Registrar.get_transfer(req, 1010, "example.com", 361)
      #=> {:ok, {%ReqDnsimple.Registrar.Transfer{}, %ReqDnsimple.Metadata{}}}
  """
  @spec get_transfer(Req.Request.t(), ReqDnsimple.account_id(), String.t(), integer()) ::
          ReqDnsimple.Response.result(Transfer.t())
  def get_transfer(req, account_id, domain, transfer_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain, transfer_id: transfer_id],
             @transfer_path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/registrar/domains/:domain/transfers/:transfer_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain, transfer_id: transfer_id],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_transfer(data) do
            {:ok, transfer} -> ReqDnsimple.Response.ok(transfer, response)
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
  Cancels a transfer using the client's configured account.

  See `cancel_transfer/4` for the domain name, transfer ID, and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` before authentication or HTTP when the
  client has no configured account.
  """
  @spec cancel_transfer(Req.Request.t(), String.t(), integer()) ::
          ReqDnsimple.Response.result(Transfer.t())
  def cancel_transfer(req, domain, transfer_id) do
    ReqDnsimple.Client.with_account(req, &cancel_transfer(req, &1, domain, transfer_id))
  end

  @doc """
  Requests cancellation of an in-progress domain transfer.

  Identifies the transfer by domain name and transfer ID, sends one bodyless
  DELETE request with retries disabled, and returns `{:ok, {transfer, %ReqDnsimple.Metadata{}}}` with a
  typed `Transfer` on HTTP 202. Cancellation is asynchronous, so the returned
  state can still be `"transferring"`; no polling or follow-up mutation occurs.
  Validation failures, malformed success bodies, other HTTP responses, and
  transport failures return `{:error, %ReqDnsimple.Error{reason: reason}}`.

  ## Example

      ReqDnsimple.Registrar.cancel_transfer(req, 1010, "example.com", 361)
      #=> {:ok, {%ReqDnsimple.Registrar.Transfer{}, %ReqDnsimple.Metadata{}}}
  """
  @spec cancel_transfer(Req.Request.t(), ReqDnsimple.account_id(), String.t(), integer()) ::
          ReqDnsimple.Response.result(Transfer.t())
  def cancel_transfer(req, account_id, domain, transfer_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain, transfer_id: transfer_id],
             @transfer_path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/registrar/domains/:domain/transfers/:transfer_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain, transfer_id: transfer_id],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 202, body: %{"data" => data}} = response} ->
          case decode_transfer(data) do
            {:ok, transfer} -> ReqDnsimple.Response.ok(transfer, response)
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
  Delegates to vanity name servers using the client's configured account.

  See `change_delegation_to_vanity/4` for the required `:name_servers` option and
  return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` before authentication
  or HTTP when the client has no configured account.
  """
  @spec change_delegation_to_vanity(Req.Request.t(), binary() | integer(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.VanityNameServer.t()])
  def change_delegation_to_vanity(req, domain, attrs) do
    ReqDnsimple.Client.with_account(req, &change_delegation_to_vanity(req, &1, domain, attrs))
  end

  @doc """
  Replaces a domain's registrar delegation with vanity name servers.

  The domain accepts a name or integer ID. The required `:name_servers` keyword
  option is a list of hostnames sent as the root JSON array, not an object.
  Explicit empty lists are preserved. Sends one PUT request with retries
  disabled and returns the ordered list of typed `ReqDnsimple.VanityNameServer`
  resources from HTTP 200, including their IP addresses and timestamps.

  This does not call the separate vanity-enablement endpoint or perform any
  follow-up requests. HTTP 412 plan restrictions, other HTTP responses,
  validation failures, malformed success bodies, and transport failures return
  `{:error, %ReqDnsimple.Error{reason: reason}}`.

  ## Example

      ReqDnsimple.Registrar.change_delegation_to_vanity(req, 1010, "example.com",
        name_servers: ["ns1.example.com", "ns2.example.com"]
      )
      #=> {:ok, {[%ReqDnsimple.VanityNameServer{}], %ReqDnsimple.Metadata{}}}
  """
  @spec change_delegation_to_vanity(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) :: ReqDnsimple.Response.result([ReqDnsimple.VanityNameServer.t()])
  def change_delegation_to_vanity(req, account_id, domain, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ),
         {:ok, validated_attrs} <- validate_delegation_attrs(attrs) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/registrar/domains/:domain/delegation/vanity",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          json: validated_attrs[:name_servers],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_vanity_name_servers(data) do
            {:ok, name_servers} -> ReqDnsimple.Response.ok(name_servers, response)
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
  Removes vanity delegation using the client's configured account.

  See `change_delegation_from_vanity/3` for domain identifiers and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` before authentication or HTTP when the
  client has no configured account.
  """
  @spec change_delegation_from_vanity(Req.Request.t(), binary() | integer()) ::
          ReqDnsimple.Response.result(nil)
  def change_delegation_from_vanity(req, domain) do
    ReqDnsimple.Client.with_account(req, &change_delegation_from_vanity(req, &1, domain))
  end

  @doc """
  Removes a domain's registrar delegation to vanity name servers.

  The domain accepts a name or integer ID. Sends one bodyless DELETE request
  with retries disabled and returns `{:ok, {nil, %ReqDnsimple.Metadata{status: 204}}}` on HTTP 204. It does not call the
  separate vanity-disablement endpoint or perform any follow-up requests.
  HTTP 412 plan restrictions, other HTTP responses, validation failures, and
  transport failures return `{:error, %ReqDnsimple.Error{reason: reason}}`.

  ## Example

      ReqDnsimple.Registrar.change_delegation_from_vanity(req, 1010, "example.com")
      #=> {:ok, {nil, %ReqDnsimple.Metadata{status: 204}}}
  """
  @spec change_delegation_from_vanity(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) :: ReqDnsimple.Response.result(nil)
  def change_delegation_from_vanity(req, account_id, domain) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/registrar/domains/:domain/delegation/vanity",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          retry: false
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

  defp validate_delegation_attrs(attrs) do
    ReqDnsimple.validate_options(attrs, @delegation_schema)
  end

  defp validate_renewal_attrs(attrs) do
    ReqDnsimple.validate_options(attrs, @renewal_schema)
  end

  defp validate_registration_attrs(attrs) do
    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @registration_schema),
         :ok <- validate_extended_attributes(validated_attrs) do
      {:ok, validated_attrs}
    end
  end

  defp validate_transfer_attrs(attrs) do
    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @transfer_schema),
         :ok <- validate_extended_attributes(validated_attrs) do
      {:ok, validated_attrs}
    end
  end

  defp validate_extended_attributes(attrs) do
    case Keyword.fetch(attrs, :extended_attributes) do
      :error -> :ok
      {:ok, extended_attributes} -> validate_extended_attributes_map(extended_attributes)
    end
  end

  defp validate_extended_attributes_map(map) when is_map(map) and not is_struct(map) do
    if Enum.all?(Map.keys(map), &is_binary/1) do
      :ok
    else
      {:error,
       %NimbleOptions.ValidationError{
         message: "expected :extended_attributes to have string keys",
         key: :extended_attributes,
         value: map
       }}
    end
  end

  defp validate_extended_attributes_map(value) do
    {:error,
     %NimbleOptions.ValidationError{
       message: "expected :extended_attributes to be a map with string keys",
       key: :extended_attributes,
       value: value
     }}
  end

  defp validate_restore_attrs(attrs) do
    ReqDnsimple.validate_options(attrs, @restore_schema)
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

  defp decode_registration(%{
         "id" => id,
         "domain_id" => domain_id,
         "registrant_id" => registrant_id,
         "period" => period,
         "state" => state,
         "auto_renew" => auto_renew,
         "whois_privacy" => whois_privacy,
         "trustee" => trustee,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(domain_id) and is_integer(registrant_id) and
              period in 1..10 and
              state in ["cancelled", "new", "registering", "registered", "failed"] and
              is_boolean(auto_renew) and is_boolean(whois_privacy) and is_boolean(trustee) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %Registration{
         id: id,
         domain_id: domain_id,
         registrant_id: registrant_id,
         period: period,
         state: state,
         auto_renew: auto_renew,
         whois_privacy: whois_privacy,
         trustee: trustee,
         created_at: created_at,
         updated_at: updated_at
       }}
    end
  end

  defp decode_registration(_data), do: :error

  defp decode_transfer(
         %{
           "id" => id,
           "domain_id" => domain_id,
           "registrant_id" => registrant_id,
           "state" => state,
           "auto_renew" => auto_renew,
           "whois_privacy" => whois_privacy,
           "trustee" => trustee,
           "created_at" => created_at,
           "updated_at" => updated_at
         } = data
       )
       when is_integer(id) and is_integer(domain_id) and is_integer(registrant_id) and
              state in ["cancelled", "new", "transferring", "transferred", "failed"] and
              is_boolean(auto_renew) and is_boolean(whois_privacy) and is_boolean(trustee) do
    status_description = Map.get(data, "status_description")

    with true <- is_nil(status_description) or is_binary(status_description),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %Transfer{
         id: id,
         domain_id: domain_id,
         registrant_id: registrant_id,
         state: state,
         auto_renew: auto_renew,
         whois_privacy: whois_privacy,
         trustee: trustee,
         status_description: status_description,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _ -> :error
    end
  end

  defp decode_transfer(_data), do: :error

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

  defp decode_whois_privacy(%{
         "id" => id,
         "domain_id" => domain_id,
         "enabled" => enabled,
         "expires_on" => expires_on,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(domain_id) and
              (is_boolean(enabled) or is_nil(enabled)) do
    with {:ok, expires_on} <- parse_optional_date(expires_on),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %WhoisPrivacy{
         id: id,
         domain_id: domain_id,
         enabled: enabled,
         expires_on: expires_on,
         created_at: created_at,
         updated_at: updated_at
       }}
    end
  end

  defp decode_whois_privacy(_data), do: :error

  defp decode_name_servers(name_servers) when is_list(name_servers) do
    if Enum.all?(name_servers, &is_binary/1), do: {:ok, name_servers}, else: :error
  end

  defp decode_name_servers(_name_servers), do: :error

  defp decode_vanity_name_servers(data) when is_list(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, name_servers} ->
      case decode_vanity_name_server(item) do
        {:ok, name_server} -> {:cont, {:ok, [name_server | name_servers]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, name_servers} -> {:ok, Enum.reverse(name_servers)}
      :error -> :error
    end
  end

  defp decode_vanity_name_servers(_data), do: :error

  defp decode_vanity_name_server(%{
         "id" => id,
         "name" => name,
         "ipv4" => ipv4,
         "ipv6" => ipv6,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_binary(name) and is_binary(ipv4) and is_binary(ipv6) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %ReqDnsimple.VanityNameServer{
         id: id,
         name: name,
         ipv4: ipv4,
         ipv6: ipv6,
         created_at: created_at,
         updated_at: updated_at
       }}
    end
  end

  defp decode_vanity_name_server(_data), do: :error

  defp decode_transfer_lock(%{"enabled" => enabled}) when is_boolean(enabled) do
    {:ok, %TransferLock{enabled: enabled}}
  end

  defp decode_transfer_lock(_data), do: :error

  defp decode_prices(
         %{
           "domain" => domain,
           "premium" => premium,
           "registration_price" => registration_price,
           "renewal_price" => renewal_price,
           "restore_price" => restore_price
         } = data
       )
       when is_binary(domain) and is_boolean(premium) and is_number(registration_price) and
              is_number(renewal_price) and is_number(restore_price) do
    with {:ok, transfer_price} <- decode_optional_price(data, "transfer_price"),
         {:ok, trustee_price} <- decode_optional_price(data, "trustee_price") do
      {:ok,
       %Prices{
         domain: domain,
         premium: premium,
         registration_price: registration_price,
         renewal_price: renewal_price,
         transfer_price: transfer_price,
         restore_price: restore_price,
         trustee_price: trustee_price
       }}
    else
      :error -> :error
    end
  end

  defp decode_prices(_data), do: :error

  defp decode_optional_price(data, key) do
    case Map.fetch(data, key) do
      :error -> {:ok, nil}
      {:ok, price} when is_number(price) -> {:ok, price}
      {:ok, _price} -> :error
    end
  end

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

  defp parse_optional_date(nil), do: {:ok, nil}
  defp parse_optional_date(value), do: parse_date(value)

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp parse_date(_value), do: :error
end
