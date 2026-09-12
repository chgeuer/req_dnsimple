defmodule ReqDnsimple.DomainResearch do
  @moduledoc """
  DNSimple Domain Research API functionality.

  Domain Research is a paid service and requires the `domain_research_read`
  OAuth scope.

  ## Example

      ReqDnsimple.DomainResearch.get_status(req, 1010, domain: "example.test")
      #=> {:ok, %ReqDnsimple.DomainResearch{}}
  """

  # https://developer.dnsimple.com/v2/domains/research/#getDomainsResearchStatus

  @type availability :: binary()

  @type t :: %__MODULE__{
          request_id: binary(),
          domain: binary(),
          availability: availability(),
          errors: [binary()]
        }

  defstruct ~w(request_id domain availability errors)a

  @path_schema [
    account_id: [type: :integer, required: true]
  ]

  @schema [
    domain: [type: :string, required: true]
  ]

  @doc """
  Researches the availability status of the supplied domain.

  This calls the dedicated paid Domain Research endpoint and does not fall back
  to a registrar availability check. The request requires the
  `domain_research_read` OAuth scope.
  """
  @spec get_status(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def get_status(req, account_id, opts) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @path_schema),
         {:ok, validated_opts} <- NimbleOptions.validate(opts, @schema) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/research/status",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          params: %{domain: Keyword.fetch!(validated_opts, :domain)}
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, research} -> {:ok, research}
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
         "request_id" => request_id,
         "domain" => domain,
         "availability" => availability,
         "errors" => errors
       })
       when is_binary(request_id) and is_binary(domain) and
              availability in ["available", "unavailable", "unknown"] and is_list(errors) do
    if Enum.all?(errors, &is_binary/1) do
      {:ok,
       %__MODULE__{
         request_id: request_id,
         domain: domain,
         availability: availability,
         errors: errors
       }}
    else
      :error
    end
  end

  defp decode(_data), do: :error
end
