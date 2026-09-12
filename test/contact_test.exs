defmodule ReqDnsimple.ContactTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "delete/3" do
    test "deleteContact sends one bodyless request and returns :ok" do
      assert :ok = ReqDnsimple.Contact.delete(client(204, ""), 1010, 1)

      assert_request(:delete, "/v2/1010/contacts/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteContact rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, contact_id} <- [
            {"1010", 1},
            {nil, 1},
            {1010, "1"},
            {1010, nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Contact.delete(request, account_id, contact_id)
      end

      refute_received {:request, _request}
    end

    test "deleteContact preserves explicit zero identifiers" do
      assert :ok = ReqDnsimple.Contact.delete(client(204, nil), 0, 0)

      assert_request(:delete, "/v2/0/contacts/0", %{}, nil)
    end

    test "deleteContact preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"contact" => ["is in use"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Contact.delete(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/contacts/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteContact rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Contact.delete(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/contacts/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteContact preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Contact.delete(transport_error_client(:timeout), 1010, 1)
    end
  end
end
