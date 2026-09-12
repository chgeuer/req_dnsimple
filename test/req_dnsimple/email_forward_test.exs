defmodule ReqDnsimple.EmailForwardTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @email_forward_data %{
    "id" => 1,
    "domain_id" => 100,
    "alias_email" => "support@example.test",
    "destination_email" => "recipient@example.test",
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00",
    "active" => false
  }

  describe "get/4" do
    test "getEmailForward sends one bodyless request and returns a typed result" do
      assert {:ok,
              %ReqDnsimple.EmailForward{
                id: 1,
                domain_id: 100,
                alias_email: "support@example.test",
                destination_email: "recipient@example.test",
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z],
                active: false
              }} =
               ReqDnsimple.EmailForward.get(
                 client(200, %{"data" => @email_forward_data}),
                 1010,
                 "example.test",
                 1
               )

      assert_request(:get, "/v2/1010/domains/example.test/email_forwards/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getEmailForward accepts integer and zero identifiers" do
      data = Map.merge(@email_forward_data, %{"id" => 0, "domain_id" => 0})

      assert {:ok, %ReqDnsimple.EmailForward{id: 0, domain_id: 0, active: false}} =
               ReqDnsimple.EmailForward.get(client(200, %{"data" => data}), 0, 0, 0)

      assert_request(:get, "/v2/0/domains/0/email_forwards/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "getEmailForward rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @email_forward_data})

      for {account_id, domain, email_forward_id} <- [
            {"1010", "example.test", 1},
            {nil, "example.test", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "example.test", "1"},
            {1010, "example.test", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.EmailForward.get(
                   request,
                   account_id,
                   domain,
                   email_forward_id
                 )
      end

      refute_received {:request, _request}
    end

    test "getEmailForward preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"email_forward" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.EmailForward.get(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:get, "/v2/1010/domains/example.test/email_forwards/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getEmailForward returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@email_forward_data, "id")},
        %{"data" => Map.put(@email_forward_data, "alias_email", nil)},
        %{"data" => Map.put(@email_forward_data, "active", 0)},
        %{"data" => Map.put(@email_forward_data, "created_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.EmailForward.get(
                   client(200, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:get, "/v2/1010/domains/example.test/email_forwards/1", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [{201, %{"data" => @email_forward_data}}, {204, nil}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.EmailForward.get(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:get, "/v2/1010/domains/example.test/email_forwards/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getEmailForward preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.EmailForward.get(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 1
               )
    end
  end

  describe "delete/4" do
    test "deleteEmailForward sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.EmailForward.delete(
                 client(204, ""),
                 1010,
                 "example.test",
                 1
               )

      assert_request(:delete, "/v2/1010/domains/example.test/email_forwards/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteEmailForward accepts an integer domain ID" do
      assert :ok = ReqDnsimple.EmailForward.delete(client(204, nil), 1010, 42, 1)

      assert_request(:delete, "/v2/1010/domains/42/email_forwards/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteEmailForward rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain, email_forward_id} <- [
            {"1010", "example.test", 1},
            {nil, "example.test", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "example.test", "1"},
            {1010, "example.test", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.EmailForward.delete(
                   request,
                   account_id,
                   domain,
                   email_forward_id
                 )
      end

      refute_received {:request, _request}
    end

    test "deleteEmailForward preserves explicit zero identifiers" do
      assert :ok = ReqDnsimple.EmailForward.delete(client(204, nil), 0, 0, 0)

      assert_request(:delete, "/v2/0/domains/0/email_forwards/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteEmailForward preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"email_forward" => ["cannot be deleted"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.EmailForward.delete(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:delete, "/v2/1010/domains/example.test/email_forwards/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteEmailForward rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.EmailForward.delete(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:delete, "/v2/1010/domains/example.test/email_forwards/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteEmailForward preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.EmailForward.delete(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 1
               )
    end
  end
end
