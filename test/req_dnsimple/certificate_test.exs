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
  @private_key_pem """
  -----BEGIN PRIVATE KEY-----
  FAKE-OFFLINE-NOT-A-PRIVATE-KEY
  -----END PRIVATE KEY-----
  """
  @download_data %{
    "server" => @server_pem,
    "root" => nil,
    "chain" => [@chain_pem]
  }
  @certificate_data %{
    "id" => 202,
    "domain_id" => 100,
    "name" => "api",
    "common_name" => "api.example.test",
    "years" => 1,
    "csr" => nil,
    "state" => "requesting",
    "auto_renew" => false,
    "alternate_names" => [],
    "authority_identifier" => "letsencrypt",
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:00:00+02:00",
    "expires_at" => nil,
    "expires_on" => nil,
    "contact_id" => nil
  }
  @purchase_data %{
    "id" => 101,
    "certificate_id" => 202,
    "state" => "new",
    "auto_renew" => false,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:01:00+02:00"
  }
  @renewal_data %{
    "id" => 505,
    "old_certificate_id" => 202,
    "new_certificate_id" => 404,
    "state" => "cancelled",
    "auto_renew" => false,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:01:00+02:00"
  }

  describe "get/4" do
    test "getCertificate sends one bodyless request and decodes a pending certificate" do
      assert {:ok,
              %ReqDnsimple.Certificate{
                id: 202,
                domain_id: 100,
                name: "api",
                common_name: "api.example.test",
                years: 1,
                csr: nil,
                state: "requesting",
                auto_renew: false,
                alternate_names: [],
                authority_identifier: "letsencrypt",
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:00:00Z],
                expires_at: nil,
                expires_on: nil,
                contact_id: nil
              }} =
               ReqDnsimple.Certificate.get(
                 client(200, %{"data" => @certificate_data}),
                 1010,
                 "example.test",
                 202
               )

      assert_request(:get, "/v2/1010/domains/example.test/certificates/202", %{}, nil)
      refute_received {:request, _request}
    end

    test "getCertificate accepts integer paths and decodes issued certificate expiry" do
      csr = """
      -----BEGIN CERTIFICATE REQUEST-----
      FAKE-OFFLINE-NOT-A-CSR
      -----END CERTIFICATE REQUEST-----
      """

      data = %{
        @certificate_data
        | "csr" => csr,
          "state" => "issued",
          "alternate_names" => ["docs.example.test"],
          "expires_at" => "2027-09-01T10:00:00+02:00",
          "expires_on" => "2027-09-01"
      }

      assert {:ok,
              %ReqDnsimple.Certificate{
                csr: ^csr,
                state: "issued",
                alternate_names: ["docs.example.test"],
                expires_at: ~U[2027-09-01 08:00:00Z],
                expires_on: ~D[2027-09-01]
              }} =
               ReqDnsimple.Certificate.get(client(200, %{"data" => data}), 0, 0, 0)

      assert_request(:get, "/v2/0/domains/0/certificates/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "getCertificate rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @certificate_data})

      for {account_id, domain, certificate_id} <- [
            {"1010", "example.test", 202},
            {nil, "example.test", 202},
            {1010, nil, 202},
            {1010, :example, 202},
            {1010, "example.test", "202"},
            {1010, "example.test", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Certificate.get(request, account_id, domain, certificate_id)
      end

      refute_received {:request, _request}
    end

    test "getCertificate preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"certificate" => ["was not found"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Certificate.get(
                   client(status, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202")
        refute_received {:request, _request}
      end
    end

    test "getCertificate returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@certificate_data, "id")},
        %{"data" => Map.put(@certificate_data, "auto_renew", 0)},
        %{"data" => Map.put(@certificate_data, "alternate_names", [nil])},
        %{"data" => Map.put(@certificate_data, "state", "unknown")},
        %{"data" => Map.put(@certificate_data, "contact_id", "202")},
        %{"data" => Map.put(@certificate_data, "created_at", "not-a-date")},
        %{"data" => Map.put(@certificate_data, "expires_on", "not-a-date")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Certificate.get(
                   client(200, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202")
        refute_received {:request, _request}
      end
    end

    test "getCertificate preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Certificate.get(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202
               )
    end
  end

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

  describe "get_private_key/4" do
    test "getCertificatePrivateKey sends one bodyless request and preserves the PEM text" do
      assert {:ok, %ReqDnsimple.Certificate.PrivateKey{private_key: @private_key_pem}} =
               ReqDnsimple.Certificate.get_private_key(
                 client(200, %{"data" => %{"private_key" => @private_key_pem}}),
                 1010,
                 "example.test",
                 202
               )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/certificates/202/private_key",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "getCertificatePrivateKey accepts an integer domain and preserves zero identifiers" do
      assert {:ok, %ReqDnsimple.Certificate.PrivateKey{private_key: @private_key_pem}} =
               ReqDnsimple.Certificate.get_private_key(
                 client(200, %{"data" => %{"private_key" => @private_key_pem}}),
                 0,
                 0,
                 0
               )

      assert_request(:get, "/v2/0/domains/0/certificates/0/private_key", %{}, nil)
    end

    test "getCertificatePrivateKey rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => %{"private_key" => @private_key_pem}})

      for {account_id, domain, certificate_id} <- [
            {"1010", "example.test", 202},
            {nil, "example.test", 202},
            {1010, nil, 202},
            {1010, :example, 202},
            {1010, "example.test", "202"},
            {1010, "example.test", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Certificate.get_private_key(
                   request,
                   account_id,
                   domain,
                   certificate_id
                 )
      end

      refute_received {:request, _request}
    end

    test "getCertificatePrivateKey preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 428, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"certificate" => ["private key is not present"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Certificate.get_private_key(
                   client(status, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202/private_key")
        refute_received {:request, _request}
      end
    end

    test "getCertificatePrivateKey returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        %{"data" => %{"private_key" => nil}},
        %{"data" => %{"private_key" => 0}}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Certificate.get_private_key(
                   client(200, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(:get, "/v2/1010/domains/example.test/certificates/202/private_key")
        refute_received {:request, _request}
      end
    end

    test "getCertificatePrivateKey preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Certificate.get_private_key(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202
               )
    end
  end

  describe "purchase_letsencrypt/3 and purchase_letsencrypt/4" do
    test "purchaseLetsencryptCertificate sends all attributes once and returns typed data" do
      attrs = [
        auto_renew: false,
        name: "api",
        alternate_names: ["docs.example.test", "status.example.test"],
        signature_algorithm: "RSA"
      ]

      assert {:ok,
              %ReqDnsimple.Certificate.Purchase{
                id: 101,
                certificate_id: 202,
                state: "new",
                auto_renew: false,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:01:00Z]
              }} =
               ReqDnsimple.Certificate.purchase_letsencrypt(
                 client(201, %{"data" => @purchase_data}),
                 1010,
                 "example.test",
                 attrs
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/certificates/letsencrypt",
        %{},
        Map.new(attrs)
      )

      refute_received {:request, _request}
    end

    test "purchaseLetsencryptCertificate leaves server defaults omitted" do
      assert {:ok, %ReqDnsimple.Certificate.Purchase{certificate_id: 202}} =
               ReqDnsimple.Certificate.purchase_letsencrypt(
                 client(201, %{"data" => @purchase_data}),
                 0,
                 42
               )

      assert_request(:post, "/v2/0/domains/42/certificates/letsencrypt")
      refute_received {:request, _request}
    end

    test "purchaseLetsencryptCertificate preserves apex, wildcard, empty, and false values" do
      for {name, alternate_names} <- [{"", []}, {"*", []}] do
        attrs = [name: name, alternate_names: alternate_names, auto_renew: false]

        assert {:ok, %ReqDnsimple.Certificate.Purchase{auto_renew: false}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   client(201, %{"data" => @purchase_data}),
                   1010,
                   "",
                   attrs
                 )

        assert_request(
          :post,
          "/v2/1010/domains//certificates/letsencrypt",
          %{},
          Map.new(attrs)
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseLetsencryptCertificate accepts every documented purchase state" do
      for state <-
            ~w(new purchased configured submitted issued rejected refunded cancelled requesting failed) do
        body = %{"data" => Map.put(@purchase_data, "state", state)}

        assert {:ok, %ReqDnsimple.Certificate.Purchase{state: ^state}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   client(201, body),
                   1010,
                   "example.test"
                 )

        assert_request(:post, "/v2/1010/domains/example.test/certificates/letsencrypt")
        refute_received {:request, _request}
      end
    end

    test "purchaseLetsencryptCertificate rejects invalid inputs before HTTP" do
      request = client(201, %{"data" => @purchase_data})

      invalid_calls = [
        {"1010", "example.test", []},
        {nil, "example.test", []},
        {1010, nil, []},
        {1010, 1.5, []},
        {1010, "example.test", [auto_renew: nil]},
        {1010, "example.test", [auto_renew: 0]},
        {1010, "example.test", [name: nil]},
        {1010, "example.test", [name: 0]},
        {1010, "example.test", [alternate_names: nil]},
        {1010, "example.test", [alternate_names: ["valid", 0]]},
        {1010, "example.test", [signature_algorithm: nil]},
        {1010, "example.test", [signature_algorithm: "DSA"]},
        {1010, "example.test", [unknown: true]},
        {1010, "example.test", %{}}
      ]

      for {account_id, domain, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   request,
                   account_id,
                   domain,
                   attrs
                 )
      end

      refute_received {:request, _request}
    end

    test "purchaseLetsencryptCertificate preserves HTTP failures and disables retries" do
      for status <- [400, 412, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"name" => ["is not available"]}
        }

        request = client(status, body) |> Req.merge(retry: :transient)

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   request,
                   1010,
                   "example.test",
                   name: "api"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt",
          %{},
          %{name: "api"}
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseLetsencryptCertificate returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@purchase_data, "id")},
        %{"data" => Map.put(@purchase_data, "id", "101")},
        %{"data" => Map.put(@purchase_data, "certificate_id", nil)},
        %{"data" => Map.put(@purchase_data, "state", "unknown")},
        %{"data" => Map.put(@purchase_data, "auto_renew", nil)},
        %{"data" => Map.put(@purchase_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(@purchase_data, "updated_at", nil)}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 201, response: ^body}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt(
                   client(201, body),
                   1010,
                   "example.test"
                 )

        assert_request(:post, "/v2/1010/domains/example.test/certificates/letsencrypt")
        refute_received {:request, _request}
      end
    end

    test "purchaseLetsencryptCertificate preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Certificate.purchase_letsencrypt(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "purchase_letsencrypt_renewal/4 and purchase_letsencrypt_renewal/5" do
    test "purchaseRenewalLetsencryptCertificate sends all attributes once and returns typed data" do
      attrs = [auto_renew: false, signature_algorithm: "RSA"]

      assert {:ok,
              %ReqDnsimple.Certificate.Renewal{
                id: 505,
                old_certificate_id: 202,
                new_certificate_id: 404,
                state: "cancelled",
                auto_renew: false,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:01:00Z]
              }} =
               ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                 client(201, %{"data" => @renewal_data}),
                 1010,
                 "example.test",
                 202,
                 attrs
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals",
        %{},
        Map.new(attrs)
      )

      refute_received {:request, _request}
    end

    test "purchaseRenewalLetsencryptCertificate leaves server defaults omitted" do
      assert {:ok, %ReqDnsimple.Certificate.Renewal{id: 505}} =
               ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                 client(201, %{"data" => @renewal_data}),
                 0,
                 0,
                 0
               )

      assert_request(
        :post,
        "/v2/0/domains/0/certificates/letsencrypt/0/renewals",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "purchaseRenewalLetsencryptCertificate accepts every documented renewal state" do
      for state <- ~w(cancelled new renewing renewed failed) do
        body = %{"data" => Map.put(@renewal_data, "state", state)}

        assert {:ok, %ReqDnsimple.Certificate.Renewal{state: ^state}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   client(201, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals"
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseRenewalLetsencryptCertificate rejects invalid inputs before HTTP" do
      request = client(201, %{"data" => @renewal_data})

      invalid_calls = [
        {"1010", "example.test", 202, []},
        {nil, "example.test", 202, []},
        {1010, nil, 202, []},
        {1010, 1.5, 202, []},
        {1010, "example.test", "202", []},
        {1010, "example.test", nil, []},
        {1010, "example.test", 202, [auto_renew: nil]},
        {1010, "example.test", 202, [auto_renew: 0]},
        {1010, "example.test", 202, [signature_algorithm: nil]},
        {1010, "example.test", 202, [signature_algorithm: "DSA"]},
        {1010, "example.test", 202, [unknown: true]},
        {1010, "example.test", 202, %{}}
      ]

      for {account_id, domain, certificate_id, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   request,
                   account_id,
                   domain,
                   certificate_id,
                   attrs
                 )
      end

      refute_received {:request, _request}
    end

    test "purchaseRenewalLetsencryptCertificate preserves HTTP failures and disables retries" do
      for status <- [400, 404, 412, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"certificate" => ["cannot be renewed"]}
        }

        request = client(status, body) |> Req.merge(retry: :transient)

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   request,
                   1010,
                   "example.test",
                   202,
                   auto_renew: false
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals",
          %{},
          %{auto_renew: false}
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseRenewalLetsencryptCertificate returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@renewal_data, "id")},
        %{"data" => Map.put(@renewal_data, "id", "505")},
        %{"data" => Map.put(@renewal_data, "old_certificate_id", nil)},
        %{"data" => Map.put(@renewal_data, "new_certificate_id", nil)},
        %{"data" => Map.put(@renewal_data, "state", "unknown")},
        %{"data" => Map.put(@renewal_data, "auto_renew", nil)},
        %{"data" => Map.put(@renewal_data, "created_at", "not-a-timestamp")},
        %{"data" => Map.put(@renewal_data, "updated_at", nil)}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 201, response: ^body}} =
                 ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                   client(201, body),
                   1010,
                   "example.test",
                   202
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/certificates/letsencrypt/202/renewals"
        )

        refute_received {:request, _request}
      end
    end

    test "purchaseRenewalLetsencryptCertificate preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 202
               )
    end
  end
end
