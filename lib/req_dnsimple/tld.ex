defmodule ReqDnsimple.Tld do
  @moduledoc """
  Supported top-level domain capabilities.

  Retrieve capabilities for a TLD or compound suffix:

      {:ok, tld} = ReqDnsimple.Tld.get(client, "com.au")

  Retrieve the registry's typed extended-attribute definitions:

      {:ok, attributes} = ReqDnsimple.Tld.list_extended_attributes(client, "co.uk")

  Name-server bounds are normalized to integers when DNSimple returns numeric
  strings. A bound omitted by the registry remains `nil`. Extended attributes
  may omit their display title, but a present title must be a string. Free-text
  attributes have an empty options list.
  """

  defmodule ExtendedAttribute do
    @moduledoc """
    A registry-specific extended attribute accepted for a TLD.
    """

    defmodule Option do
      @moduledoc """
      One allowed value for a registry-specific extended attribute.
      """

      @type t :: %__MODULE__{
              title: binary(),
              value: binary(),
              description: binary()
            }

      defstruct ~w(title value description)a
    end

    @type t :: %__MODULE__{
            name: binary(),
            description: binary(),
            required: boolean(),
            options: [Option.t()],
            title: binary() | nil
          }

    defstruct ~w(name description required options title)a
  end

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

  @doc """
  Retrieves the registry-specific extended-attribute definitions for a TLD.

  The non-paginated result preserves arbitrary registry names and option values
  as strings. An omitted attribute title is returned as `nil`.
  """
  @spec list_extended_attributes(Req.Request.t(), binary()) ::
          {:ok, [ExtendedAttribute.t()]} | {:error, term()}
  def list_extended_attributes(req, tld) do
    with {:ok, _validated_path} <- NimbleOptions.validate([tld: tld], @path_schema) do
      req =
        Req.merge(req,
          method: :get,
          url: "/tlds/:tld/extended_attributes",
          path_params_style: :colon,
          path_params: [tld: tld]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response}
        when is_list(data) ->
          case decode_extended_attributes(data) do
            {:ok, attributes} -> {:ok, attributes}
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
    with {:ok, name_server_min} <- decode_optional_bound(data, "name_server_min"),
         {:ok, name_server_max} <- decode_optional_bound(data, "name_server_max") do
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

  defp decode_optional_bound(data, key) do
    case Map.fetch(data, key) do
      :error -> {:ok, nil}
      {:ok, value} -> decode_bound(value)
    end
  end

  defp decode_bound(value) when is_integer(value), do: {:ok, value}

  defp decode_bound(value) when is_binary(value) do
    case Regex.run(~r/\A[0-9]+\z/, value) do
      [_digits] -> {:ok, String.to_integer(value)}
      _other -> :error
    end
  end

  defp decode_bound(_value), do: :error

  defp decode_extended_attributes(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, attributes} ->
      case decode_extended_attribute(item) do
        {:ok, attribute} -> {:cont, {:ok, [attribute | attributes]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, attributes} -> {:ok, Enum.reverse(attributes)}
      :error -> :error
    end
  end

  defp decode_extended_attribute(
         %{
           "name" => name,
           "description" => description,
           "required" => required,
           "options" => options
         } = data
       )
       when is_binary(name) and is_binary(description) and is_boolean(required) and
              is_list(options) do
    with {:ok, title} <- decode_optional_title(data),
         {:ok, options} <- decode_extended_attribute_options(options) do
      {:ok,
       %ExtendedAttribute{
         name: name,
         description: description,
         required: required,
         options: options,
         title: title
       }}
    else
      _invalid -> :error
    end
  end

  defp decode_extended_attribute(_data), do: :error

  defp decode_optional_title(data) do
    case Map.fetch(data, "title") do
      :error -> {:ok, nil}
      {:ok, title} when is_binary(title) -> {:ok, title}
      {:ok, _invalid} -> :error
    end
  end

  defp decode_extended_attribute_options(options) do
    Enum.reduce_while(options, {:ok, []}, fn
      %{"title" => title, "value" => value, "description" => description}, {:ok, decoded_options}
      when is_binary(title) and is_binary(value) and is_binary(description) ->
        option = %ExtendedAttribute.Option{
          title: title,
          value: value,
          description: description
        }

        {:cont, {:ok, [option | decoded_options]}}

      _invalid, _acc ->
        {:halt, :error}
    end)
    |> case do
      {:ok, options} -> {:ok, Enum.reverse(options)}
      :error -> :error
    end
  end
end
