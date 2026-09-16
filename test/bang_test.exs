defmodule ReqDnsimple.BangTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  alias ReqDnsimple.{Error, Metadata}

  @zone_data %{
    "id" => 1,
    "account_id" => 1010,
    "name" => "example.test",
    "active" => true,
    "reverse" => false,
    "secondary" => false,
    "last_transferred_at" => nil,
    "created_at" => "2026-09-01T10:00:00Z",
    "updated_at" => "2026-09-01T10:30:00Z"
  }

  describe "zone-listing bang functions" do
    test "list_zones!/2 returns zones with metadata and preserves the configured client" do
      req =
        client(200, %{"data" => [@zone_data]}, self(), [{"x-request-id", "bang-success"}])
        |> Req.merge(base_url: "https://proxy.example/gateway/v2")

      assert {[%ReqDnsimple.Zone{id: 1, name: "example.test", active: true}],
              %Metadata{status: 200, request_id: "bang-success"}} =
               ReqDnsimple.list_zones!(req, "1010")

      assert_receive {:request, request}
      assert request.method == :get
      assert request.url.scheme == "https"
      assert request.url.host == "proxy.example"
      assert request.url.path == "/gateway/v2/1010/zones"
      assert URI.decode_query(request.url.query || "") == %{}
      assert request.body in [nil, ""]
      assert Req.Request.get_header(request, "authorization") == ["Bearer dnsimple_u_fake-token"]
      refute_received {:request, _request}
    end

    test "list!/2 supports omitted options" do
      assert {[], %Metadata{status: 200, pagination: nil}} =
               ReqDnsimple.Zone.list!(client(200, %{"data" => []}), 1010)

      assert_request(:get, "/v2/1010/zones")
      refute_received {:request, _request}
    end

    test "list!/3 preserves filters and one-page behavior" do
      body = %{
        "data" => [@zone_data],
        "pagination" => %{
          "current_page" => 2,
          "per_page" => 1,
          "total_pages" => 3,
          "total_entries" => 3
        }
      }

      pagination = body["pagination"]

      assert {[%ReqDnsimple.Zone{id: 1}],
              %Metadata{status: 200, pagination: ^pagination, pages: []}} =
               ReqDnsimple.Zone.list!(client(200, body), 1010,
                 name_like: "example",
                 sort: [name: :desc],
                 page: 2,
                 per_page: 1
               )

      assert_request(:get, "/v2/1010/zones", %{
        "name_like" => "example",
        "sort" => "name:desc",
        "page" => 2,
        "per_page" => 1
      })

      refute_received {:request, _request}
    end

    test "API failures raise the same structured error returned by the tuple API" do
      body = %{"message" => "Zone listing is not permitted", "policy" => "zone-list"}

      req =
        client(403, body, self(), [
          {"x-request-id", "bang-failure"},
          {"etag", ~s("failure-etag")},
          {"retry-after", "60"}
        ])

      assert {:error,
              %Error{
                reason: %{status: 403, response: ^body},
                metadata: %Metadata{
                  status: 403,
                  request_id: "bang-failure",
                  etag: ~s("failure-etag"),
                  retry_after: "60"
                }
              } = returned_error} =
               ReqDnsimple.list_zones(req, 1010)

      assert_request(:get, "/v2/1010/zones")

      error =
        assert_raise ReqDnsimple.Error, fn ->
          ReqDnsimple.list_zones!(req, 1010)
        end

      assert error == returned_error
      assert Exception.message(error) == "DNSimple request failed with HTTP status 403"
      assert_request(:get, "/v2/1010/zones")
      refute_received {:request, _request}
    end

    test "not-found errors preserve their original atom reason" do
      error =
        assert_raise ReqDnsimple.Error, fn ->
          ReqDnsimple.list_zones!(
            client(404, %{"message" => "Not found"}, self(), [
              {"x-request-id", "bang-not-found"}
            ]),
            1010
          )
        end

      assert error.reason == :not_found
      assert error.metadata == %Metadata{status: 404, request_id: "bang-not-found"}
      assert Exception.message(error) == "DNSimple resource not found"
      assert_request(:get, "/v2/1010/zones")
      refute_received {:request, _request}
    end

    test "invalid options raise a structured error retaining the validation exception before dispatch" do
      req = client(200, %{"data" => []})

      assert {:error,
              %Error{reason: %NimbleOptions.ValidationError{key: :page}, metadata: nil} =
                returned_error} = ReqDnsimple.Zone.list(req, 1010, page: 0)

      error =
        assert_raise Error, fn ->
          ReqDnsimple.Zone.list!(req, 1010, page: 0)
        end

      assert error == returned_error
      refute_received {:request, _request}
    end

    test "transport failures raise a structured error retaining the original exception" do
      error =
        assert_raise Error, fn ->
          ReqDnsimple.list_zones!(transport_error_client(:econnrefused), 1010)
        end

      assert %Req.TransportError{reason: :econnrefused} = error.reason
      assert error.metadata == nil
    end
  end

  describe "unwrap!/1" do
    test "preserves arbitrary successful values, metadata tuples, and standalone :ok" do
      for value <- [
            nil,
            false,
            0,
            [],
            %{},
            {[:zone], %{"current_page" => 2}},
            {[:zone], %Metadata{status: 200}},
            {nil, %Metadata{status: 204}}
          ] do
        assert ReqDnsimple.unwrap!({:ok, value}) === value
      end

      assert ReqDnsimple.unwrap!(:ok) == :ok
    end

    test "raises existing exception structs unchanged" do
      for original <- [
            ArgumentError.exception("invalid input"),
            %NimbleOptions.ValidationError{message: "invalid page", key: :page, value: 0},
            %Req.TransportError{reason: :econnrefused},
            %Error{
              reason: :not_found,
              metadata: %Metadata{status: 404, request_id: "original-error"}
            }
          ] do
        assert assert_raise(original.__struct__, fn ->
                 ReqDnsimple.unwrap!({:error, original})
               end) == original
      end
    end

    test "retains directly supplied HTTP-shaped reasons without fabricating metadata or dumping content" do
      reason = %{
        status: 429,
        response: %{"message" => "Rate limited", "private_detail" => "do-not-print"},
        retry_after: "60"
      }

      error = assert_raise ReqDnsimple.Error, fn -> ReqDnsimple.unwrap!({:error, reason}) end

      assert error.reason == reason
      assert error.metadata == nil
      assert Exception.message(error) == "DNSimple request failed with HTTP status 429"
    end

    test "retains non-HTTP reasons without assuming an HTTP response shape" do
      reason = %{message: "request failed", detail: "do-not-print"}
      error = assert_raise ReqDnsimple.Error, fn -> ReqDnsimple.unwrap!({:error, reason}) end

      assert error.reason == reason
      assert error.metadata == nil
      assert Exception.message(error) == "DNSimple request failed"
    end

    test "rejects unsupported result shapes rather than silently returning them" do
      for result <- [nil, false, [], {:user, %{"id" => 1}}, {:ok, :unexpected, :extra}] do
        assert_raise ArgumentError, "expected {:ok, value}, :ok, or {:error, reason}", fn ->
          ReqDnsimple.unwrap!(result)
        end
      end
    end
  end

  test "bang entry points provide compiled docs and typespecs for code help" do
    for {module, function, arity} <- [
          {ReqDnsimple, :list_zones!, 2},
          {ReqDnsimple, :unwrap!, 1},
          {ReqDnsimple.Zone, :list!, 3}
        ] do
      assert {:docs_v1, _, :elixir, _, _, _, entries} = Code.fetch_docs(module)

      entry =
        Enum.find(entries, fn {identifier, _, _, _, _} ->
          identifier == {:function, function, arity}
        end)

      assert {{:function, ^function, ^arity}, _, _, %{"en" => documentation}, _} = entry
      assert documentation =~ "Raises"

      assert {:ok, specs} = Code.Typespec.fetch_specs(module)
      assert Enum.any?(specs, fn {identifier, _} -> identifier == {function, arity} end)
    end
  end
end
