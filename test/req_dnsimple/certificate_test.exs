defmodule ReqDnsimple.CertificateTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @server_pem """
  -----BEGIN CERTIFICATE-----
  FAKE-OFFLINE-SERVER-NOT-A-CERTIFICATE
  -----END CERTIFICATE-----
  """
  @chain_pem """
  -----BEGIN CERTIFICATE-----
  FAKE-OFFLINE-INTERMEDIATE
  -----END CERTIFICATE-----
  """
  @download_data %{
    "server" => @server_pem,
    "root" => nil,
    "chain" => [@chain_pem]
  }

  describe "download/4" do
    test "downloadCertificate sends one bodyless request and preserves the typed PEM bundle" do
      assert {:ok,
              %ReqDnsimple.Certificate.Download{
                server: @server_pem,
                root: nil,
                chain: [@chain_pem]
              }} =
               ReqDnsimple.Certificate.download(
                 client(200, %{"data" => @download_data}),
                 1010,
                 "example.test",
                 202
               )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/certificates/202/download",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "downloadCertificate accepts an integer domain and preserves zero identifiers" do
      root_pem = """
      -----BEGIN CERTIFICATE-----
      FAKE-OFFLINE-ROOT
      -----END CERTIFICATE-----
      """

      data = %{@download_data | "root" => root_pem, "chain" => []}

      assert {:ok, %ReqDnsimple.Certificate.Download{root: ^root_pem, chain: []}} =
               ReqDnsimple.Certificate.download(
                 client(200, %{"data" => data}),
                 0,
                 0,
                 0
               )

      assert_request(:get, "/v2/0/domains/0/certificates/0/download", %{}, nil)
    end

    test "downloadCertificate rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @download_data})

      for {account_id, domain, certificate_id} <- [
            {"1010", "example.test", 202},
            {nil, "example.test", 202},
            {1010, nil, 202},
            {1010, :example, 202},
            {1010, "example.test", "202"},
            {1010, "example.test", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Certificate.download(request, account_id, domain, certificate_id)
      end

      refute_received {:request, _request}
    end

    test "downloadCertificate preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 428, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"certificate" => ["is not downloadable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Certificate.download(
                   client(status, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202/download")
        refute_received {:request, _request}
      end
    end

    test "downloadCertificate returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@download_data, "server")},
        %{"data" => Map.put(@download_data, "server", nil)},
        %{"data" => Map.put(@download_data, "root", 0)},
        %{"data" => Map.put(@download_data, "chain", nil)},
        %{"data" => Map.put(@download_data, "chain", [nil])}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Certificate.download(
                   client(200, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202/download")
        refute_received {:request, _request}
      end
    end

    test "downloadCertificate preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Certificate.download(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202
               )
    end
  end
end
