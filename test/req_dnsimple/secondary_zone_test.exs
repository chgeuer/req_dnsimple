defmodule ReqDnsimple.SecondaryZoneTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @zone_data %{
    "id" => 1,
    "account_id" => 1010,
    "name" => "secondary.example.test",
    "reverse" => false,
    "secondary" => true,
    "last_transferred_at" => nil,
    "active" => true,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  describe "create/3" do
    test "createSecondaryZone sends the name once and returns the typed zone" do
      assert {:ok,
              %ReqDnsimple.Zone{
                id: 1,
                account_id: 1010,
                name: "secondary.example.test",
                reverse: false,
                secondary: true,
                last_transferred_at: nil,
                active: true,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.SecondaryZone.create(
                 client(201, %{"data" => @zone_data}),
                 1010,
                 name: "secondary.example.test"
               )

      assert_request(
        :post,
        "/v2/1010/secondary_dns/zones",
        %{},
        %{name: "secondary.example.test"}
      )

      refute_received {:request, _request}
    end

    test "createSecondaryZone tolerates an omitted active field without fabricating it" do
      data = Map.delete(@zone_data, "active")

      assert {:ok, %ReqDnsimple.Zone{active: nil, secondary: true}} =
               ReqDnsimple.SecondaryZone.create(
                 client(201, %{"data" => data}),
                 1010,
                 name: "secondary.example.test"
               )

      assert_request(
        :post,
        "/v2/1010/secondary_dns/zones",
        %{},
        %{name: "secondary.example.test"}
      )

      refute_received {:request, _request}
    end

    test "createSecondaryZone preserves zero account identifiers and an empty name" do
      assert {:ok, %ReqDnsimple.Zone{}} =
               ReqDnsimple.SecondaryZone.create(
                 client(201, %{"data" => @zone_data}),
                 0,
                 name: ""
               )

      assert_request(:post, "/v2/0/secondary_dns/zones", %{}, %{name: ""})
      refute_received {:request, _request}
    end

    test "createSecondaryZone rejects invalid paths and attributes before HTTP" do
      request = client(201, %{"data" => @zone_data})

      for {account_id, attrs} <- [
            {"1010", [name: "secondary.example.test"]},
            {nil, [name: "secondary.example.test"]},
            {1010, []},
            {1010, [:invalid]},
            {1010, [{:name}]},
            {1010, [name: nil]},
            {1010, [name: 42]},
            {1010, [name: []]},
            {1010, [name: "secondary.example.test", unknown: true]}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.SecondaryZone.create(request, account_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "createSecondaryZone preserves documented and shared HTTP failures" do
      for status <- [400, 406, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"name" => ["cannot be verified"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.SecondaryZone.create(
                   client(status, body),
                   1010,
                   name: "secondary.example.test"
                 )

        assert_request(
          :post,
          "/v2/1010/secondary_dns/zones",
          %{},
          %{name: "secondary.example.test"}
        )

        refute_received {:request, _request}
      end
    end

    test "createSecondaryZone returns explicit errors for malformed success responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => []},
        %{"data" => Map.delete(@zone_data, "last_transferred_at")},
        %{"data" => Map.put(@zone_data, "active", nil)},
        %{"data" => Map.put(@zone_data, "secondary", false)},
        %{"data" => Map.put(@zone_data, "last_transferred_at", "not-a-timestamp")},
        %{"data" => Map.put(@zone_data, "created_at", nil)}
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 201, response: ^body}} =
                 ReqDnsimple.SecondaryZone.create(
                   client(201, body),
                   1010,
                   name: "secondary.example.test"
                 )

        assert_request(
          :post,
          "/v2/1010/secondary_dns/zones",
          %{},
          %{name: "secondary.example.test"}
        )

        refute_received {:request, _request}
      end

      assert {:error, %{status: 200, response: %{"data" => @zone_data}}} =
               ReqDnsimple.SecondaryZone.create(
                 client(200, %{"data" => @zone_data}),
                 1010,
                 name: "secondary.example.test"
               )

      assert_request(
        :post,
        "/v2/1010/secondary_dns/zones",
        %{},
        %{name: "secondary.example.test"}
      )

      refute_received {:request, _request}
    end

    test "createSecondaryZone preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.SecondaryZone.create(
                 transport_error_client(:timeout),
                 1010,
                 name: "secondary.example.test"
               )
    end
  end
end
