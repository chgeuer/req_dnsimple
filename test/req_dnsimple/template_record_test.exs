defmodule ReqDnsimple.TemplateRecordTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "get/4" do
    test "getTemplateRecord retrieves one typed record with one bodyless request" do
      body = template_record_body(0)

      assert {:ok,
              %ReqDnsimple.TemplateRecord{
                id: 1,
                template_id: 1,
                name: "",
                content: "mail.{{domain}}",
                ttl: 0,
                priority: 0,
                type: "MX",
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:00:00Z]
              }} =
               ReqDnsimple.TemplateRecord.get(
                 client(200, body),
                 1010,
                 "offline-template",
                 1
               )

      assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTemplateRecord normalizes legacy numeric-string and nullable priorities" do
      for {wire_priority, priority} <- [{"10", 10}, {"0010", 10}, {-1, -1}, {nil, nil}] do
        assert {:ok, %ReqDnsimple.TemplateRecord{priority: ^priority}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(200, template_record_body(wire_priority)),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord accepts integer, zero, and empty template identifiers" do
      for {account_id, template, record_id} <- [
            {1010, 42, 1},
            {0, 0, 0},
            {1010, "", 1}
          ] do
        assert {:ok, %ReqDnsimple.TemplateRecord{}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(200, template_record_body(nil)),
                   account_id,
                   template,
                   record_id
                 )

        assert_request(
          :get,
          "/v2/#{account_id}/templates/#{template}/records/#{record_id}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord rejects invalid path parameters before HTTP" do
      request = client(200, template_record_body(nil))

      for {account_id, template, record_id} <- [
            {"1010", "offline-template", 1},
            {nil, "offline-template", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "offline-template", "1"},
            {1010, "offline-template", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.TemplateRecord.get(
                   request,
                   account_id,
                   template,
                   record_id
                 )
      end

      refute_received {:request, _request}
    end

    test "getTemplateRecord rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(template_record_body(nil), ["data", "created_at"], "not-a-timestamp"),
        put_in(template_record_body(nil), ["data", "ttl"], -1),
        put_in(template_record_body(nil), ["data", "priority"], "high"),
        put_in(template_record_body(nil), ["data", "priority"], "+10"),
        put_in(template_record_body(nil), ["data", "priority"], "10\n"),
        put_in(template_record_body(nil), ["data", "type"], "INVALID")
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(200, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["was not found"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(status, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.TemplateRecord.get(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template",
                 1
               )
    end
  end

  describe "delete/4" do
    test "deleteTemplateRecord sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.TemplateRecord.delete(
                 client(204, nil),
                 1010,
                 "offline-template",
                 1
               )

      assert_request(
        :delete,
        "/v2/1010/templates/offline-template/records/1",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "deleteTemplateRecord accepts integer, zero, and empty template identifiers" do
      for {account_id, template, record_id} <- [
            {1010, 42, 1},
            {0, 0, 0},
            {1010, "", 1}
          ] do
        assert :ok =
                 ReqDnsimple.TemplateRecord.delete(
                   client(204, nil),
                   account_id,
                   template,
                   record_id
                 )

        assert_request(
          :delete,
          "/v2/#{account_id}/templates/#{template}/records/#{record_id}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "deleteTemplateRecord rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, template, record_id} <- [
            {"1010", "offline-template", 1},
            {nil, "offline-template", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "offline-template", "1"},
            {1010, "offline-template", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.TemplateRecord.delete(
                   request,
                   account_id,
                   template,
                   record_id
                 )
      end

      refute_received {:request, _request}
    end

    test "deleteTemplateRecord preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["cannot be deleted"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.TemplateRecord.delete(
                   client(status, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(
          :delete,
          "/v2/1010/templates/offline-template/records/1",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "deleteTemplateRecord rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.TemplateRecord.delete(
                   client(status, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(
          :delete,
          "/v2/1010/templates/offline-template/records/1",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "deleteTemplateRecord preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.TemplateRecord.delete(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template",
                 1
               )
    end
  end

  defp template_record_body(priority) do
    %{
      "data" => %{
        "id" => 1,
        "template_id" => 1,
        "name" => "",
        "content" => "mail.{{domain}}",
        "ttl" => 0,
        "priority" => priority,
        "type" => "MX",
        "created_at" => "2026-09-01T10:00:00+02:00",
        "updated_at" => "2026-09-01T10:00:00+02:00"
      }
    }
  end
end
