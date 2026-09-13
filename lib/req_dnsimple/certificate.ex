defmodule ReqDnsimple.Certificate do
  @moduledoc """
  DNSimple certificate API functionality.

  ## Example

      ReqDnsimple.Certificate.list_page(req, 1010, "example.test",
        sort: [id: :asc, common_name: :desc],
        page: 2,
        per_page: 30
      )
      #=> {:ok, {[%ReqDnsimple.Certificate{}], %{"current_page" => 2}}}

      ReqDnsimple.Certificate.list_all(req, 1010, "example.test",
        sort: [expiration: :asc],
        per_page: 100
      )
      #=> {:ok, [%ReqDnsimple.Certificate{}]}

      ReqDnsimple.Certificate.get(req, 1010, "example.test", 202)
      #=> {:ok, %ReqDnsimple.Certificate{}}

      ReqDnsimple.Certificate.purchase_letsencrypt(req, 1010, "example.test",
        auto_renew: false,
        name: "api",
        alternate_names: ["docs.example.test"],
        signature_algorithm: "RSA"
      )
      #=> {:ok, %ReqDnsimple.Certificate.Purchase{}}

      ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
        req,
        1010,
        "example.test",
        202,
        auto_renew: false,
        signature_algorithm: "RSA"
      )
      #=> {:ok, %ReqDnsimple.Certificate.Renewal{}}

      ReqDnsimple.Certificate.issue_letsencrypt(req, 1010, "example.test", 202)
      #=> {:ok, %ReqDnsimple.Certificate{state: "requesting"}}

      ReqDnsimple.Certificate.issue_letsencrypt_renewal(
        req,
        1010,
        "example.test",
        202,
        505
      )
      #=> {:ok, %ReqDnsimple.Certificate{state: "requesting"}}

      ReqDnsimple.Certificate.download(req, 1010, "example.test", 202)
      #=> {:ok, %ReqDnsimple.Certificate.Download{}}

      ReqDnsimple.Certificate.get_private_key(req, 1010, "example.test", 202)
      #=> {:ok, %ReqDnsimple.Certificate.PrivateKey{}}
  """

  # https://developer.dnsimple.com/v2/certificates/

  @type t :: %__MODULE__{
          id: integer(),
          domain_id: integer(),
          name: binary(),
          common_name: binary(),
          years: integer(),
          csr: binary() | nil,
          state: binary(),
          auto_renew: boolean(),
          alternate_names: [binary()],
          authority_identifier: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          expires_on: Date.t() | nil,
          contact_id: integer() | nil
        }

  defstruct ~w(id domain_id name common_name years csr state auto_renew alternate_names
               authority_identifier created_at updated_at expires_at expires_on contact_id)a

  defmodule Download do
    @moduledoc """
    A certificate's PEM-encoded server, root, and intermediate certificates.
    """

    @type t :: %__MODULE__{
            server: binary(),
            root: binary() | nil,
            chain: [binary()]
          }

    defstruct [:server, :root, chain: []]
  end

  defmodule PrivateKey do
    @moduledoc """
    A certificate's byte-preserved PEM-encoded private key.
    """

    @type t :: %__MODULE__{private_key: binary()}

    defstruct [:private_key]
  end

  defmodule Purchase do
    @moduledoc """
    A Let's Encrypt certificate purchase awaiting separate issuance.
    """

    @type t :: %__MODULE__{
            id: integer(),
            certificate_id: integer(),
            state: binary(),
            auto_renew: boolean(),
            created_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    defstruct [:id, :certificate_id, :state, :auto_renew, :created_at, :updated_at]
  end

  defmodule Renewal do
    @moduledoc """
    A Let's Encrypt certificate renewal order awaiting separate issuance.
    """

    @type t :: %__MODULE__{
            id: integer() | nil,
            old_certificate_id: integer() | nil,
            new_certificate_id: integer() | nil,
            state: binary() | nil,
            auto_renew: boolean() | nil,
            created_at: DateTime.t() | nil,
            updated_at: DateTime.t() | nil
          }

    defstruct [
      :id,
      :old_certificate_id,
      :new_certificate_id,
      :state,
      :auto_renew,
      :created_at,
      :updated_at
    ]
  end

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    certificate_id: [type: :integer, required: true]
  ]

  @issue_renewal_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    certificate_id: [type: :integer, required: true],
    renewal_id: [type: :integer, required: true]
  ]

  @purchase_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @purchase_schema [
    auto_renew: [type: :boolean],
    name: [type: :string],
    alternate_names: [type: {:list, :string}],
    signature_algorithm: [type: {:in, ["ECDSA", "RSA"]}]
  ]

  @renewal_schema [
    auto_renew: [type: :boolean],
    signature_algorithm: [type: {:in, ["ECDSA", "RSA"]}]
  ]

  @list_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :common_name, :expiration]]},
      doc: "Sort by id, common_name, or expiration. Format: [id: :asc, common_name: :desc]"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of certificates per page"]
  ]

  @doc """
  Lists one page of certificates for a domain.

  Supports ordered `:sort` terms for `:id`, `:common_name`, and `:expiration`,
  plus `:page` and `:per_page`. Omitting `:sort` preserves the API's default
  descending-ID order. The returned pagination metadata retains its string keys.

  ## Example

      ReqDnsimple.Certificate.list_page(
        req,
        1010,
        "example.test",
        sort: [id: :asc, common_name: :desc],
        page: 2,
        per_page: 30
      )
      #=> {:ok, {[%ReqDnsimple.Certificate{}], %{"current_page" => 2}}}
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
             @purchase_path_schema
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
  Lists one page of certificates for a domain.

  This is a convenience alias for `list_page/4`; it never enumerates additional
  pages implicitly.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list(req, account_id, domain, opts \\ []), do: list_page(req, account_id, domain, opts)

  @doc """
  Enumerates every page of certificates for a domain in server order.

  Enumeration always begins at page one, so an explicit `:page` option is
  rejected. Sorting and `:per_page` are retained for every request.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def list_all(req, account_id, domain, opts \\ []) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, domain, &1))
  end

  @doc """
  Orders a Let's Encrypt certificate without issuing or downloading it.

  By default DNSimple covers `www`; custom names, SANs, and wildcards depend on
  the account plan. Optional settings are `:auto_renew`, `:name`,
  `:alternate_names`, and `:signature_algorithm` (`"ECDSA"` or `"RSA"`).
  Omitted settings are left to DNSimple's server defaults, while explicit
  `false`, empty names, and empty alternate-name lists are preserved.

  Returns a typed `Purchase` containing both the order ID and the distinct
  certificate ID. The function sends exactly one request and does not issue,
  download, deploy, or otherwise follow up on the certificate.
  """
  @spec purchase_letsencrypt(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) ::
          {:ok, Purchase.t()} | {:error, term()}
  def purchase_letsencrypt(req, account_id, domain, attrs \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @purchase_path_schema
           ),
         {:ok, validated_attrs} <- validate_purchase_attrs(attrs) do
      request_options = [
        method: :post,
        url: "/:account_id/domains/:domain/certificates/letsencrypt",
        path_params_style: :colon,
        path_params: [account_id: account_id, domain: domain],
        retry: false
      ]

      request_options =
        if validated_attrs == [] do
          request_options
        else
          Keyword.put(request_options, :json, Map.new(validated_attrs))
        end

      case Req.request(Req.merge(req, request_options)) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode_purchase(data) do
            {:ok, purchase} -> {:ok, purchase}
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
  Orders a Let's Encrypt renewal without issuing or deploying it.

  Optional settings are `:auto_renew` and `:signature_algorithm` (`"ECDSA"` or
  `"RSA"`). Omitted settings are left to DNSimple's server defaults, while an
  explicit `false` value is preserved.

  Returns a typed `Renewal` with distinct old and new certificate IDs. The
  function sends exactly one request and does not issue the renewal or perform
  any other follow-up operation.
  """
  @spec purchase_letsencrypt_renewal(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer(),
          keyword()
        ) ::
          {:ok, Renewal.t()} | {:error, term()}
  def purchase_letsencrypt_renewal(req, account_id, domain, certificate_id, attrs \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               certificate_id: certificate_id
             ],
             @path_schema
           ),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @renewal_schema) do
      request_options = [
        method: :post,
        url: "/:account_id/domains/:domain/certificates/letsencrypt/:certificate_id/renewals",
        path_params_style: :colon,
        path_params: [
          account_id: account_id,
          domain: domain,
          certificate_id: certificate_id
        ],
        retry: false
      ]

      request_options =
        if validated_attrs == [] do
          request_options
        else
          Keyword.put(request_options, :json, Map.new(validated_attrs))
        end

      case Req.request(Req.merge(req, request_options)) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
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
  Requests issuance of an ordered Let's Encrypt certificate.

  The final argument is the certificate ID returned by `Purchase`, not the
  purchase order ID. This sends one bodyless request and returns the certificate
  in its current state without polling, downloading, or deploying it.
  """
  @spec issue_letsencrypt(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) ::
          {:ok, t()} | {:error, term()}
  def issue_letsencrypt(req, account_id, domain, certificate_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               certificate_id: certificate_id
             ],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/domains/:domain/certificates/letsencrypt/:certificate_id/issue",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            certificate_id: certificate_id
          ],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 202, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, certificate} -> {:ok, certificate}
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
  Requests issuance of a previously ordered Let's Encrypt renewal.

  `certificate_id` is the original certificate ID and `renewal_id` is the
  renewal order ID. This sends one bodyless request and returns the replacement
  certificate in its current state without polling, downloading, or deploying
  it.
  """
  @spec issue_letsencrypt_renewal(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer(),
          integer()
        ) ::
          {:ok, t()} | {:error, term()}
  def issue_letsencrypt_renewal(req, account_id, domain, certificate_id, renewal_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               certificate_id: certificate_id,
               renewal_id: renewal_id
             ],
             @issue_renewal_path_schema
           ) do
      req =
        Req.merge(req,
          method: :post,
          url:
            "/:account_id/domains/:domain/certificates/letsencrypt/:certificate_id/renewals/:renewal_id/issue",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            certificate_id: certificate_id,
            renewal_id: renewal_id
          ],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 202, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, certificate} -> {:ok, certificate}
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
  Retrieves certificate metadata by account, domain name or ID, and certificate ID.

  Pending certificates preserve nullable CSR and expiry fields. Issued
  certificate expiry timestamps and dates are decoded to their Elixir types.
  """
  @spec get(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, domain, certificate_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               certificate_id: certificate_id
             ],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain/certificates/:certificate_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            certificate_id: certificate_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, certificate} -> {:ok, certificate}
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
  Downloads a certificate's PEM bundle without writing it to the filesystem.

  The PEM strings are returned byte-for-byte as supplied by DNSimple. A
  certificate that is not yet downloadable returns the API's HTTP 428 error.
  """
  @spec download(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) ::
          {:ok, Download.t()} | {:error, term()}
  def download(req, account_id, domain, certificate_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               certificate_id: certificate_id
             ],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain/certificates/:certificate_id/download",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            certificate_id: certificate_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_download(data) do
            {:ok, download} -> {:ok, download}
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
  Retrieves a certificate's private key without parsing or persisting it.

  The PEM string is returned byte-for-byte as supplied by DNSimple. A
  certificate without an available private key returns the API's HTTP 428 error.
  """
  @spec get_private_key(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) ::
          {:ok, PrivateKey.t()} | {:error, term()}
  def get_private_key(req, account_id, domain, certificate_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               certificate_id: certificate_id
             ],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain/certificates/:certificate_id/private_key",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            certificate_id: certificate_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_private_key(data) do
            {:ok, private_key} -> {:ok, private_key}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp validate_purchase_attrs(attrs),
    do: ReqDnsimple.validate_options(attrs, @purchase_schema)

  defp decode_renewal(data) when is_map(data) do
    with {:ok, id} <- decode_optional(data, "id", &is_integer/1),
         {:ok, old_certificate_id} <-
           decode_optional(data, "old_certificate_id", &is_integer/1),
         {:ok, new_certificate_id} <-
           decode_optional(data, "new_certificate_id", &is_integer/1),
         {:ok, state} <-
           decode_optional(
             data,
             "state",
             &(&1 in ["cancelled", "new", "renewing", "renewed", "failed"])
           ),
         {:ok, auto_renew} <- decode_optional(data, "auto_renew", &is_boolean/1),
         {:ok, created_at} <- decode_optional(data, "created_at", &parse_datetime/1),
         {:ok, updated_at} <- decode_optional(data, "updated_at", &parse_datetime/1) do
      {:ok,
       %Renewal{
         id: id,
         old_certificate_id: old_certificate_id,
         new_certificate_id: new_certificate_id,
         state: state,
         auto_renew: auto_renew,
         created_at: created_at,
         updated_at: updated_at
       }}
    end
  end

  defp decode_renewal(_data), do: :error

  defp decode_optional(data, key, validator) do
    case Map.fetch(data, key) do
      :error -> {:ok, nil}
      {:ok, value} -> validate_optional_value(value, validator)
    end
  end

  defp validate_optional_value(value, validator) do
    case validator.(value) do
      true -> {:ok, value}
      {:ok, decoded} -> {:ok, decoded}
      _ -> :error
    end
  end

  defp decode_purchase(%{
         "id" => id,
         "certificate_id" => certificate_id,
         "state" => state,
         "auto_renew" => auto_renew,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(certificate_id) and
              state in [
                "new",
                "purchased",
                "configured",
                "submitted",
                "issued",
                "rejected",
                "refunded",
                "cancelled",
                "requesting",
                "failed"
              ] and is_boolean(auto_renew) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %Purchase{
         id: id,
         certificate_id: certificate_id,
         state: state,
         auto_renew: auto_renew,
         created_at: created_at,
         updated_at: updated_at
       }}
    end
  end

  defp decode_purchase(_data), do: :error

  defp decode_private_key(%{"private_key" => private_key}) when is_binary(private_key) do
    {:ok, %PrivateKey{private_key: private_key}}
  end

  defp decode_private_key(_data), do: :error

  defp decode_download(%{"server" => server, "root" => root, "chain" => chain})
       when is_binary(server) and (is_binary(root) or is_nil(root)) and is_list(chain) do
    if Enum.all?(chain, &is_binary/1) do
      {:ok, %Download{server: server, root: root, chain: chain}}
    else
      :error
    end
  end

  defp decode_download(_data), do: :error

  defp decode_page(data, pagination) when is_list(data) do
    with {:ok, certificates} <- decode_many(data),
         true <- valid_pagination?(pagination) do
      {:ok, {certificates, pagination}}
    else
      _error -> :error
    end
  end

  defp decode_page(_data, _pagination), do: :error

  defp decode_many(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, certificates} ->
      case decode(item) do
        {:ok, certificate} ->
          {:cont, {:ok, [certificate | certificates]}}

        :error ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, certificates} -> {:ok, Enum.reverse(certificates)}
      :error -> :error
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
      url: "/:account_id/domains/:domain/certificates",
      path_params_style: :colon,
      path_params: [account_id: account_id, domain: domain],
      params: params
    )
    |> Req.request()
  end

  defp decode(
         %{
           "id" => id,
           "domain_id" => domain_id,
           "name" => name,
           "common_name" => common_name,
           "years" => years,
           "csr" => csr,
           "state" => state,
           "auto_renew" => auto_renew,
           "alternate_names" => alternate_names,
           "authority_identifier" => authority_identifier,
           "created_at" => created_at,
           "updated_at" => updated_at,
           "expires_at" => expires_at,
           "expires_on" => expires_on
         } = data
       )
       when is_integer(id) and is_integer(domain_id) and is_binary(name) and
              is_binary(common_name) and is_integer(years) and
              (is_binary(csr) or is_nil(csr)) and
              state in [
                "new",
                "purchased",
                "configured",
                "submitted",
                "issued",
                "rejected",
                "refunded",
                "cancelled",
                "requesting",
                "failed"
              ] and is_boolean(auto_renew) and is_list(alternate_names) and
              authority_identifier in ["comodo", "rapidssl", "letsencrypt"] do
    contact_id = Map.get(data, "contact_id")

    with true <- Enum.all?(alternate_names, &is_binary/1),
         true <- is_integer(contact_id) or is_nil(contact_id),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at),
         {:ok, expires_at} <- parse_optional_datetime(expires_at),
         {:ok, expires_on} <- parse_optional_date(expires_on) do
      {:ok,
       %__MODULE__{
         id: id,
         domain_id: domain_id,
         name: name,
         common_name: common_name,
         years: years,
         csr: csr,
         state: state,
         auto_renew: auto_renew,
         alternate_names: alternate_names,
         authority_identifier: authority_identifier,
         created_at: created_at,
         updated_at: updated_at,
         expires_at: expires_at,
         expires_on: expires_on,
         contact_id: contact_id
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp parse_optional_datetime(nil), do: {:ok, nil}
  defp parse_optional_datetime(value), do: parse_datetime(value)

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp parse_optional_date(nil), do: {:ok, nil}

  defp parse_optional_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp parse_optional_date(_value), do: :error
end
