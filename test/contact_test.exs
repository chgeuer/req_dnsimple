defmodule ReqDnsimple.ContactTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @contact_data %{
    "id" => 1,
    "account_id" => 1010,
    "label" => "Offline contact",
    "first_name" => "Test",
    "last_name" => "Contact",
    "organization_name" => "Example Test Organization",
    "job_title" => "Test Operator",
    "address1" => "1 Example Street",
    "address2" => nil,
    "city" => "Roma",
    "state_province" => "RM",
    "postal_code" => "00100",
    "country" => "IT",
    "phone" => "+12025550123",
    "fax" => nil,
    "email" => "contact@example.test",
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  @contact_attrs [
    first_name: "Test",
    last_name: "Contact",
    email: "contact@example.test",
    phone: "+12025550123",
    address1: "1 Example Street",
    city: "Roma",
    state_province: "RM",
    postal_code: "00100",
    country: "IT",
    label: "Offline contact",
    organization_name: "Example Test Organization",
    job_title: "Test Operator",
    address2: nil,
    fax: nil
  ]

  describe "create/3" do
    test "createContact sends every supported attribute once and returns a typed contact" do
      assert {:ok,
              %ReqDnsimple.Contact{
                id: 1,
                account_id: 1010,
                label: "Offline contact",
                first_name: "Test",
                last_name: "Contact",
                organization_name: "Example Test Organization",
                job_title: "Test Operator",
                address1: "1 Example Street",
                address2: nil,
                city: "Roma",
                state_province: "RM",
                postal_code: "00100",
                country: "IT",
                phone: "+12025550123",
                fax: nil,
                email: "contact@example.test",
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.Contact.create(
                 client(201, %{"data" => @contact_data}),
                 1010,
                 @contact_attrs
               )

      assert_request(:post, "/v2/1010/contacts", %{}, Map.new(@contact_attrs))
      refute_received {:request, _request}
    end

    test "createContact preserves omitted options, empty strings, nullable values, and zero account" do
      attrs = [
        first_name: "",
        last_name: "",
        email: "",
        phone: "",
        address1: "",
        city: "",
        state_province: "",
        postal_code: "00100",
        country: "IT",
        label: "",
        address2: nil,
        fax: nil
      ]

      assert {:ok, %ReqDnsimple.Contact{address2: nil, fax: nil}} =
               ReqDnsimple.Contact.create(
                 client(201, %{"data" => @contact_data}),
                 0,
                 attrs
               )

      assert_request(:post, "/v2/0/contacts", %{}, Map.new(attrs))
      refute_received {:request, _request}
    end

    test "createContact rejects invalid paths and attributes before HTTP" do
      request = client(201, %{"data" => @contact_data})

      invalid_calls = [
        {"1010", @contact_attrs},
        {nil, @contact_attrs},
        {1010, [:invalid]},
        {1010, [{:name}]},
        {1010, []},
        {1010, Keyword.delete(@contact_attrs, :first_name)},
        {1010, Keyword.put(@contact_attrs, :first_name, false)},
        {1010, Keyword.put(@contact_attrs, :last_name, 0)},
        {1010, Keyword.put(@contact_attrs, :email, [])},
        {1010, Keyword.put(@contact_attrs, :phone, %{})},
        {1010, Keyword.put(@contact_attrs, :phone, nil)},
        {1010, Keyword.put(@contact_attrs, :postal_code, 100)},
        {1010, Keyword.put(@contact_attrs, :country, "it")},
        {1010, Keyword.put(@contact_attrs, :country, "ITA")},
        {1010, Keyword.put(@contact_attrs, :country, "IT\n")},
        {1010, Keyword.put(@contact_attrs, :address2, false)},
        {1010, Keyword.put(@contact_attrs, :fax, 0)},
        {1010, Keyword.delete(@contact_attrs, :job_title)},
        {1010, Keyword.put(@contact_attrs, :unknown, true)}
      ]

      for {account_id, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Contact.create(request, account_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "createContact preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"country" => ["is invalid"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Contact.create(client(status, body), 1010, @contact_attrs)

        assert_request(:post, "/v2/1010/contacts", %{}, Map.new(@contact_attrs))
        refute_received {:request, _request}
      end
    end

    test "createContact returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@contact_data, "id")},
        %{"data" => Map.delete(@contact_data, "address2")},
        %{"data" => Map.put(@contact_data, "address2", false)},
        %{"data" => Map.put(@contact_data, "fax", 0)},
        %{"data" => Map.put(@contact_data, "country", nil)},
        %{"data" => Map.put(@contact_data, "created_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 201, response: ^body}} =
                 ReqDnsimple.Contact.create(client(201, body), 1010, @contact_attrs)

        assert_request(:post, "/v2/1010/contacts", %{}, Map.new(@contact_attrs))
        refute_received {:request, _request}
      end
    end

    test "createContact rejects an unexpected success status" do
      body = %{"data" => @contact_data}

      assert {:error, %{status: 200, response: ^body}} =
               ReqDnsimple.Contact.create(client(200, body), 1010, @contact_attrs)

      assert_request(:post, "/v2/1010/contacts", %{}, Map.new(@contact_attrs))
    end

    test "createContact preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Contact.create(
                 transport_error_client(:timeout),
                 1010,
                 @contact_attrs
               )
    end
  end

  describe "update/4" do
    test "updateContact patches every supported attribute once and returns a typed contact" do
      assert {:ok,
              %ReqDnsimple.Contact{
                id: 1,
                account_id: 1010,
                label: "Offline contact",
                first_name: "Test",
                last_name: "Contact",
                organization_name: "Example Test Organization",
                job_title: "Test Operator",
                address1: "1 Example Street",
                address2: nil,
                city: "Roma",
                state_province: "RM",
                postal_code: "00100",
                country: "IT",
                phone: "+12025550123",
                fax: nil,
                email: "contact@example.test",
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.Contact.update(
                 client(200, %{"data" => @contact_data}),
                 1010,
                 1,
                 @contact_attrs
               )

      assert_request(:patch, "/v2/1010/contacts/1", %{}, Map.new(@contact_attrs))
      refute_received {:request, _request}
    end

    test "updateContact preserves omitted fields, empty strings, nullable values, and zero IDs" do
      for {account_id, contact_id, attrs, expected_body} <- [
            {1010, 1, [label: ""], %{"label" => ""}},
            {1010, 1, [address2: nil, fax: nil], %{"address2" => nil, "fax" => nil}},
            {0, 0, [], %{}}
          ] do
        assert {:ok, %ReqDnsimple.Contact{postal_code: "00100", address2: nil, fax: nil}} =
                 ReqDnsimple.Contact.update(
                   client(200, %{"data" => @contact_data}),
                   account_id,
                   contact_id,
                   attrs
                 )

        assert_request(
          :patch,
          "/v2/#{account_id}/contacts/#{contact_id}",
          %{},
          expected_body
        )

        refute_received {:request, _request}
      end
    end

    test "updateContact rejects invalid paths and attributes before HTTP" do
      request = client(200, %{"data" => @contact_data})

      invalid_cases =
        [
          {"1010", 1, [label: "Updated"]},
          {nil, 1, [label: "Updated"]},
          {1010, "1", [label: "Updated"]},
          {1010, nil, [label: "Updated"]},
          {1010, 1, [:invalid]},
          {1010, 1, [{:name}]},
          {1010, 1, [organization_name: "Example"]},
          {1010, 1, [unknown: true]}
        ] ++
          for field <- [
                :label,
                :first_name,
                :last_name,
                :address1,
                :city,
                :state_province,
                :postal_code,
                :email,
                :phone,
                :organization_name,
                :job_title
              ],
              value <- [nil, false, 0, [], %{}] do
            {1010, 1, [{field, value}]}
          end ++
          for field <- [:address2, :fax],
              value <- [false, 0, [], %{}] do
            {1010, 1, [{field, value}]}
          end ++
          for value <- [nil, false, 0, [], %{}, "it", "ITA", "IT\n"] do
            {1010, 1, [country: value]}
          end

      for {account_id, contact_id, attrs} <- invalid_cases do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Contact.update(request, account_id, contact_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "updateContact preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"country" => ["is invalid"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Contact.update(
                   client(status, body),
                   1010,
                   1,
                   label: "Updated"
                 )

        assert_request(:patch, "/v2/1010/contacts/1", %{}, %{"label" => "Updated"})
        refute_received {:request, _request}
      end
    end

    test "updateContact returns explicit errors for malformed success and unexpected status" do
      malformed_responses = [
        {200, %{}},
        {200, %{"data" => nil}},
        {200, %{"data" => Map.delete(@contact_data, "id")}},
        {200, %{"data" => Map.delete(@contact_data, "address2")}},
        {200, %{"data" => Map.put(@contact_data, "address2", false)}},
        {200, %{"data" => Map.put(@contact_data, "fax", 0)}},
        {200, %{"data" => Map.put(@contact_data, "country", nil)}},
        {200, %{"data" => Map.put(@contact_data, "created_at", "not-a-timestamp")}},
        {201, %{"data" => @contact_data}}
      ]

      for {status, body} <- malformed_responses do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Contact.update(
                   client(status, body),
                   1010,
                   1,
                   label: "Updated"
                 )

        assert_request(:patch, "/v2/1010/contacts/1", %{}, %{"label" => "Updated"})
        refute_received {:request, _request}
      end
    end

    test "updateContact preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Contact.update(
                 transport_error_client(:timeout),
                 1010,
                 1,
                 label: "Updated"
               )
    end
  end

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
