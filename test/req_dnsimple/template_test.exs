defmodule ReqDnsimple.TemplateTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "apply/4" do
    test "applyTemplateToDomain sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.Template.apply(
                 client(204, nil),
                 1010,
                 "example.test",
                 "offline-template"
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/templates/offline-template",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "applyTemplateToDomain accepts integer, zero, and empty identifiers" do
      for {account_id, domain, template} <- [{0, 0, 0}, {1010, "", ""}] do
        assert :ok =
                 ReqDnsimple.Template.apply(
                   client(204, nil),
                   account_id,
                   domain,
                   template
                 )

        assert_request(
          :post,
          "/v2/#{account_id}/domains/#{domain}/templates/#{template}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyTemplateToDomain rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, domain, template} <- [
            {"1010", "example.test", "offline-template"},
            {nil, "example.test", "offline-template"},
            {1010, nil, "offline-template"},
            {1010, 1.5, "offline-template"},
            {1010, "example.test", nil},
            {1010, "example.test", 1.5}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Template.apply(request, account_id, domain, template)
      end

      refute_received {:request, _request}
    end

    test "applyTemplateToDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template" => ["cannot be applied"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Template.apply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-template"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/templates/offline-template",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyTemplateToDomain rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Template.apply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-template"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/templates/offline-template",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyTemplateToDomain preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Template.apply(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 "offline-template"
               )
    end
  end

  describe "delete/3" do
    test "deleteTemplate sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.Template.delete(
                 client(204, nil),
                 1010,
                 "offline-template"
               )

      assert_request(:delete, "/v2/1010/templates/offline-template", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteTemplate accepts integer, zero, and empty template identifiers" do
      for {account_id, template} <- [{1010, 42}, {0, 0}, {1010, ""}] do
        assert :ok = ReqDnsimple.Template.delete(client(204, nil), account_id, template)

        assert_request(:delete, "/v2/#{account_id}/templates/#{template}", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteTemplate rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, template} <- [
            {"1010", "offline-template"},
            {nil, "offline-template"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Template.delete(request, account_id, template)
      end

      refute_received {:request, _request}
    end

    test "deleteTemplate preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template" => ["cannot be deleted"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Template.delete(
                   client(status, body),
                   1010,
                   "offline-template"
                 )

        assert_request(:delete, "/v2/1010/templates/offline-template", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteTemplate rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Template.delete(
                   client(status, body),
                   1010,
                   "offline-template"
                 )

        assert_request(:delete, "/v2/1010/templates/offline-template", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteTemplate preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Template.delete(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template"
               )
    end
  end
end
