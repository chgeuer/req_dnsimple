defmodule ReqDnsimple.Tld do
  @moduledoc """
  Supported top-level domain capabilities.

  Retrieve capabilities for a TLD or compound suffix:

      {:ok, tld} = ReqDnsimple.Tld.get(client, "com.au")

  Name-server bounds are normalized to integers when DNSimple returns numeric
  strings. A bound omitted by the registry remains `nil`.
  """

  @type t :: %__MODULE__{
          tld: binary(),
          tld_type: 1 | 2 | 3,
          whois_privacy: boolean(),
          auto_renew_only: boolean(),
          idn: boolean(),
          minimum_registration: integer(),
          registration_enabled: boolean(),
          renewal_enabled: boolean(),
          transfer_enabled: boolean(),
          dnssec_interface_type: binary(),
          name_server_min: integer() | nil,
          name_server_max: integer() | nil,
          trustee_service_enabled: boolean(),
          trustee_service_required: boolean()
        }

  defstruct ~w(
    tld
    tld_type
    whois_privacy
    auto_renew_only
    idn
    minimum_registration
    registration_enabled
    renewal_enabled
    transfer_enabled
    dnssec_interface_type
    name_server_min
    name_server_max
    trustee_service_enabled
    trustee_service_required
  )a

  @path_schema [
    tld: [type: :string, required: true]
  ]

  @doc """
  Retrieves one supported TLD and its registration, DNSSEC, privacy, and
  name-server capabilities.

  The suffix is sent unchanged, including compound suffixes such as `com.au`.
  """
  @spec get(Req.Request.t(), binary()) :: {:ok, t()} | {:error, term()}
  def get(req, tld) do
    with {:ok, _validated_path} <- NimbleOptions.validate([tld: tld], @path_schema) do
      req =
        Req.merge(req,
          method: :get,
          url: "/tlds/:tld",
          path_params_style: :colon,
          path_params: [tld: tld]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, tld} -> {:ok, tld}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp decode(
         %{
           "tld" => tld,
           "tld_type" => tld_type,
           "whois_privacy" => whois_privacy,
           "auto_renew_only" => auto_renew_only,
           "idn" => idn,
           "minimum_registration" => minimum_registration,
           "registration_enabled" => registration_enabled,
           "renewal_enabled" => renewal_enabled,
           "transfer_enabled" => transfer_enabled,
           "dnssec_interface_type" => dnssec_interface_type,
           "trustee_service_enabled" => trustee_service_enabled,
           "trustee_service_required" => trustee_service_required
         } = data
       )
       when is_binary(tld) and tld_type in [1, 2, 3] and is_boolean(whois_privacy) and
              is_boolean(auto_renew_only) and is_boolean(idn) and
              is_integer(minimum_registration) and is_boolean(registration_enabled) and
              is_boolean(renewal_enabled) and is_boolean(transfer_enabled) and
              dnssec_interface_type in ["ds", "key"] and is_boolean(trustee_service_enabled) and
              is_boolean(trustee_service_required) do
    with {:ok, name_server_min} <- decode_bound(Map.get(data, "name_server_min")),
         {:ok, name_server_max} <- decode_bound(Map.get(data, "name_server_max")) do
      {:ok,
       %__MODULE__{
         tld: tld,
         tld_type: tld_type,
         whois_privacy: whois_privacy,
         auto_renew_only: auto_renew_only,
         idn: idn,
         minimum_registration: minimum_registration,
         registration_enabled: registration_enabled,
         renewal_enabled: renewal_enabled,
         transfer_enabled: transfer_enabled,
         dnssec_interface_type: dnssec_interface_type,
         name_server_min: name_server_min,
         name_server_max: name_server_max,
         trustee_service_enabled: trustee_service_enabled,
         trustee_service_required: trustee_service_required
       }}
    else
      :error -> :error
    end
  end

  defp decode(_data), do: :error

  defp decode_bound(nil), do: {:ok, nil}
  defp decode_bound(value) when is_integer(value), do: {:ok, value}

  defp decode_bound(value) when is_binary(value) do
    case Integer.parse(value) do
      {bound, ""} when bound >= 0 -> {:ok, bound}
      _other -> :error
    end
  end

  defp decode_bound(_value), do: :error
end
