defmodule ReqDnsimple.SecondaryZone do
  @moduledoc """
  DNSimple secondary-zone creation.

  ## Example

      ReqDnsimple.SecondaryZone.create(
        req,
        1010,
        name: "secondary.example.test"
      )
      #=> {:ok, %ReqDnsimple.Zone{secondary: true}}

  Creation sends one request and returns the existing `ReqDnsimple.Zone` type.
  DNSimple may require ownership verification and a subscription; this client
  does not change delegation, create primary servers, or perform verification.
  """

  # https://developer.dnsimple.com/v2/secondary-dns/#createSecondaryZone

  @path_schema [
    account_id: [type: :integer, required: true]
  ]

  @create_schema [
    name: [type: :string, required: true]
  ]

  @doc """
  Creates a secondary DNS zone.

  `name` is required. Ownership-verification and subscription failures are
  returned as HTTP errors without any preflight or follow-up request.
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, ReqDnsimple.Zone.t()} | {:error, term()}
  def create(req, account_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @path_schema),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/secondary_dns/zones",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case ReqDnsimple.Zone.decode(data, :optional) do
            {:ok, %ReqDnsimple.Zone{secondary: true} = zone} -> {:ok, zone}
            _invalid -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end
end
