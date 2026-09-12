defmodule ReqDnsimple.TemplateRecordTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

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
end
