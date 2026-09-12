defmodule ReqDnsimple.RegistrarTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "authorize_transfer_out/3" do
    test "authorizeDomainTransferOut sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.Registrar.authorize_transfer_out(
                 client(204, ""),
                 1010,
                 "example.test"
               )

      assert_request(
        :post,
        "/v2/1010/registrar/domains/example.test/authorize_transfer_out",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "authorizeDomainTransferOut preserves explicit zero and empty identifiers" do
      assert :ok = ReqDnsimple.Registrar.authorize_transfer_out(client(204, nil), 0, "")

      assert_request(:post, "/v2/0/registrar/domains//authorize_transfer_out", %{}, nil)
      refute_received {:request, _request}
    end

    test "authorizeDomainTransferOut rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain_name} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 42},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Registrar.authorize_transfer_out(
                   request,
                   account_id,
                   domain_name
                 )
      end

      refute_received {:request, _request}
    end

    test "authorizeDomainTransferOut preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["cannot be transferred"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.authorize_transfer_out(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/authorize_transfer_out",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "authorizeDomainTransferOut rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Registrar.authorize_transfer_out(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/domains/example.test/authorize_transfer_out",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "authorizeDomainTransferOut preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Registrar.authorize_transfer_out(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end
end
