ExUnit.start()

Req.default_options(
  adapter: fn request ->
    raise "unexpected unmocked HTTP request: #{request.method} #{request.url}"
  end
)

defmodule ReqDnsimple.TestSupport do
  import ExUnit.Assertions

  def client(status, body, test_pid \\ self()) do
    adapter = fn request ->
      send(test_pid, {:request, request})
      {request, %Req.Response{status: status, body: body}}
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end

  def transport_error_client(reason) do
    adapter = fn request ->
      {request, %Req.TransportError{reason: reason}}
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
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

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_values(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_string(value)} end)
  end
end
