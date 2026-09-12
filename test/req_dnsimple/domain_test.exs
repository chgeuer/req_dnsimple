defmodule ReqDnsimple.DomainTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "delete/3" do
    test "deleteDomain sends one bodyless request and returns :ok" do
      assert :ok = ReqDnsimple.Domain.delete(client(204, ""), 1010, "example.test")

      assert_request(:delete, "/v2/1010/domains/example.test", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomain accepts an integer domain ID" do
      assert :ok = ReqDnsimple.Domain.delete(client(204, nil), 1010, 42)

      assert_request(:delete, "/v2/1010/domains/42", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomain rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Domain.delete(request, account_id, domain)
      end

      refute_received {:request, _request}
    end

    test "deleteDomain preserves explicit zero identifiers" do
      assert :ok = ReqDnsimple.Domain.delete(client(204, nil), 0, 0)

      assert_request(:delete, "/v2/0/domains/0", %{}, nil)
    end

    test "deleteDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["cannot be deleted"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Domain.delete(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomain rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Domain.delete(client(status, body), 1010, "example.test")

        assert_request(:delete, "/v2/1010/domains/example.test", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomain preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Domain.delete(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end
end
