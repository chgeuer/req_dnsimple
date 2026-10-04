ExUnit.start()

defmodule ReqDnsimple.TestAdapter do
  @moduledoc false

  # Req 0.7 deprecates function adapters and warns on every request that uses
  # one, so tests give their adapter functions to this module adapter instead.
  # A function the request carries answers it, then one installed for the
  # sending process; any other request is unexpected and unmocked.

  @private_key :req_dnsimple_test_adapter
  @process_key {__MODULE__, :local}

  @doc "Req.new/1, except that a function `:adapter` runs through this module."
  def new(options), do: merge(Req.new(), options)

  @doc "Req.merge/2, except that a function `:adapter` runs through this module."
  def merge(request, options) do
    {adapter, options} = Keyword.pop!(options, :adapter)

    request
    |> Req.merge(options)
    |> put(adapter)
  end

  defp put(request, adapter) when is_function(adapter, 1) do
    request
    |> Req.merge(adapter: __MODULE__)
    |> Req.Request.put_private(@private_key, adapter)
  end

  @doc """
  Answers the requests the calling process sends without an adapter function
  of their own with `adapter`. Returns this module, for Req.default_options/1.
  """
  def local(adapter) when is_function(adapter, 1) do
    Process.put(@process_key, adapter)
    __MODULE__
  end

  @doc false
  def run(request) do
    case Req.Request.get_private(request, @private_key) || Process.get(@process_key) do
      adapter when is_function(adapter, 1) ->
        adapter.(request)

      nil ->
        raise "unexpected unmocked HTTP request: #{request.method} #{request.url}"
    end
  end
end

Req.default_options(adapter: ReqDnsimple.TestAdapter)

defmodule ReqDnsimple.TestSupport do
  import ExUnit.Assertions

  def client(status, body, test_pid \\ self(), headers \\ []) do
    adapter = fn request ->
      send(test_pid, {:request, request})
      {request, Req.Response.new(status: status, body: body, headers: headers)}
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> ReqDnsimple.TestAdapter.merge(adapter: adapter, retry: false)
  end

  def transport_error_client(reason) do
    adapter = fn request ->
      {request, %Req.TransportError{reason: reason}}
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> ReqDnsimple.TestAdapter.merge(adapter: adapter, retry: false)
  end

  def assert_request(method, path, query \\ %{}, body \\ nil) do
    assert_receive {:request, request}
    assert request.method == method
    assert request.url.path == path
    assert URI.decode_query(request.url.query || "") == stringify_values(query)

    if body do
      assert Jason.decode!(request.body) == stringify_keys(body)
    else
      assert request.body in [nil, ""]
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp stringify_values(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_string(value)} end)
  end
end
