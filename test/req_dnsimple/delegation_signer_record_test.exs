defmodule ReqDnsimple.DelegationSignerRecordTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "delete/4" do
    test "deleteDomainDelegationSignerRecord sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.DelegationSignerRecord.delete(
                 client(204, ""),
                 1010,
                 "example.test",
                 1
               )

      assert_request(:delete, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomainDelegationSignerRecord accepts an integer domain ID" do
      assert :ok =
               ReqDnsimple.DelegationSignerRecord.delete(client(204, nil), 1010, 42, 1)

      assert_request(:delete, "/v2/1010/domains/42/ds_records/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomainDelegationSignerRecord rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, domain, ds_record_id} <- [
            {"1010", "example.test", 1},
            {nil, "example.test", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "example.test", "1"},
            {1010, "example.test", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.DelegationSignerRecord.delete(
                   request,
                   account_id,
                   domain,
                   ds_record_id
                 )
      end

      refute_received {:request, _request}
    end

    test "deleteDomainDelegationSignerRecord preserves explicit zero identifiers" do
      assert :ok = ReqDnsimple.DelegationSignerRecord.delete(client(204, nil), 0, 0, 0)

      assert_request(:delete, "/v2/0/domains/0/ds_records/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteDomainDelegationSignerRecord preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"ds_record" => ["cannot be deleted"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DelegationSignerRecord.delete(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:delete, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomainDelegationSignerRecord rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DelegationSignerRecord.delete(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(:delete, "/v2/1010/domains/example.test/ds_records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteDomainDelegationSignerRecord preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.DelegationSignerRecord.delete(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 1
               )
    end
  end
end
