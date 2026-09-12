defmodule ReqDnsimple.WebhookTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

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
