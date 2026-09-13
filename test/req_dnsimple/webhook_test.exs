defmodule ReqDnsimple.WebhookTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @webhook_data %{
    "id" => 1,
    "url" => "https://receiver.example.test/events",
    "suppressed_at" => nil
  }

  describe "create/3" do
    test "createWebhook sends the complete HTTPS URL once and returns a typed webhook" do
      url = "https://receiver.example.test/events?source=dnsimple"
      data = Map.put(@webhook_data, "url", url)

      assert {:ok,
              %ReqDnsimple.Webhook{
                id: 1,
                url: ^url,
                suppressed_at: nil
              }} =
               ReqDnsimple.Webhook.create(
                 client(201, %{"data" => data}),
                 1010,
                 url: url
               )

      assert_request(:post, "/v2/1010/webhooks", %{}, %{"url" => url})
      refute_received {:request, _request}
    end

    test "createWebhook parses a non-null offset suppression timestamp" do
      data = Map.put(@webhook_data, "suppressed_at", "2026-09-01T10:00:00+02:00")

      assert {:ok,
              %ReqDnsimple.Webhook{
                suppressed_at: ~U[2026-09-01 08:00:00Z]
              }} =
               ReqDnsimple.Webhook.create(
                 client(201, %{"data" => data}),
                 0,
                 url: "https://receiver.example.test/events"
               )

      assert_request(
        :post,
        "/v2/0/webhooks",
        %{},
        %{"url" => "https://receiver.example.test/events"}
      )
    end

    test "createWebhook rejects invalid paths and attributes before HTTP" do
      request = client(201, %{"data" => @webhook_data})

      for {account_id, attrs} <- [
            {"1010", [url: "https://receiver.example.test/events"]},
            {nil, [url: "https://receiver.example.test/events"]},
            {1010, [:invalid]},
            {1010, [{:url}]},
            {1010, []},
            {1010, [url: nil]},
            {1010, [url: false]},
            {1010, [url: 0]},
            {1010, [url: ""]},
            {1010, [url: "http://receiver.example.test/events"]},
            {1010, [url: "https:///events"]},
            {1010, [url: "not a URI"]},
            {1010, [url: "https://receiver.example.test/events", unknown: true]}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Webhook.create(request, account_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "createWebhook preserves documented and shared HTTP failures" do
      url = "https://receiver.example.test/events"

      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"url" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Webhook.create(client(status, body), 1010, url: url)

        assert_request(:post, "/v2/1010/webhooks", %{}, %{"url" => url})
        refute_received {:request, _request}
      end
    end

    test "createWebhook returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@webhook_data, "id")},
        %{"data" => Map.delete(@webhook_data, "url")},
        %{"data" => Map.delete(@webhook_data, "suppressed_at")},
        %{"data" => Map.put(@webhook_data, "id", "1")},
        %{"data" => Map.put(@webhook_data, "url", nil)},
        %{"data" => Map.put(@webhook_data, "suppressed_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 201, response: ^body}} =
                 ReqDnsimple.Webhook.create(
                   client(201, body),
                   1010,
                   url: "https://receiver.example.test/events"
                 )

        assert_request(
          :post,
          "/v2/1010/webhooks",
          %{},
          %{"url" => "https://receiver.example.test/events"}
        )

        refute_received {:request, _request}
      end
    end

    test "createWebhook rejects an unexpected success status" do
      body = %{"data" => @webhook_data}

      assert {:error, %{status: 200, response: ^body}} =
               ReqDnsimple.Webhook.create(
                 client(200, body),
                 1010,
                 url: "https://receiver.example.test/events"
               )

      assert_request(
        :post,
        "/v2/1010/webhooks",
        %{},
        %{"url" => "https://receiver.example.test/events"}
      )
    end

    test "createWebhook preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Webhook.create(
                 transport_error_client(:timeout),
                 1010,
                 url: "https://receiver.example.test/events"
               )
    end
  end

  describe "get/3" do
    test "getWebhook sends one bodyless request and returns an unsuppressed webhook" do
      assert {:ok,
              %{
                __struct__: ReqDnsimple.Webhook,
                id: 1,
                url: "https://receiver.example.test/events",
                suppressed_at: nil
              }} =
               ReqDnsimple.Webhook.get(
                 client(200, %{"data" => @webhook_data}),
                 1010,
                 1
               )

      assert_request(:get, "/v2/1010/webhooks/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getWebhook parses a non-null offset suppression timestamp" do
      data = Map.put(@webhook_data, "suppressed_at", "2026-09-01T10:00:00+02:00")

      assert {:ok,
              %{
                __struct__: ReqDnsimple.Webhook,
                suppressed_at: ~U[2026-09-01 08:00:00Z]
              }} = ReqDnsimple.Webhook.get(client(200, %{"data" => data}), 1010, "0042")

      assert_request(:get, "/v2/1010/webhooks/0042", %{}, nil)
      refute_received {:request, _request}
    end

    test "getWebhook preserves explicit zero identifiers" do
      data = Map.put(@webhook_data, "id", 0)

      assert {:ok, %{__struct__: ReqDnsimple.Webhook, id: 0}} =
               ReqDnsimple.Webhook.get(client(200, %{"data" => data}), 0, 0)

      assert_request(:get, "/v2/0/webhooks/0", %{}, nil)
    end

    test "getWebhook rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @webhook_data})

      for {account_id, webhook_id} <- [
            {"1010", 1},
            {nil, 1},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Webhook.get(request, account_id, webhook_id)
      end

      refute_received {:request, _request}
    end

    test "getWebhook preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"webhook" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Webhook.get(client(status, body), 1010, 1)

        assert_request(:get, "/v2/1010/webhooks/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getWebhook returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@webhook_data, "id")},
        %{"data" => Map.delete(@webhook_data, "url")},
        %{"data" => Map.delete(@webhook_data, "suppressed_at")},
        %{"data" => Map.put(@webhook_data, "id", "1")},
        %{"data" => Map.put(@webhook_data, "url", nil)},
        %{"data" => Map.put(@webhook_data, "suppressed_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Webhook.get(client(200, body), 1010, 1)

        assert_request(:get, "/v2/1010/webhooks/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getWebhook preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Webhook.get(transport_error_client(:timeout), 1010, 1)
    end
  end

  describe "delete/3" do
    test "deleteWebhook sends one bodyless request and returns :ok" do
      assert :ok = ReqDnsimple.Webhook.delete(client(204, nil), 1010, 1)

      assert_request(:delete, "/v2/1010/webhooks/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteWebhook preserves integer, zero, and numeric-string webhook identifiers" do
      for {account_id, webhook_id} <- [{1010, 42}, {0, 0}, {1010, "0042"}] do
        assert :ok = ReqDnsimple.Webhook.delete(client(204, ""), account_id, webhook_id)

        assert_request(:delete, "/v2/#{account_id}/webhooks/#{webhook_id}", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteWebhook rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, webhook_id} <- [
            {"1010", 1},
            {nil, 1},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Webhook.delete(request, account_id, webhook_id)
      end

      refute_received {:request, _request}
    end

    test "deleteWebhook preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"webhook" => ["cannot be deleted"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Webhook.delete(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/webhooks/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteWebhook rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Webhook.delete(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/webhooks/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteWebhook preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Webhook.delete(transport_error_client(:timeout), 1010, 1)
    end
  end
end
