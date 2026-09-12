defmodule ReqDnsimple.TldTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "get/2" do
    test "getTld retrieves one typed TLD without changing a compound suffix" do
      body = tld_body()

      assert {:ok,
              %ReqDnsimple.Tld{
                tld: "com.au",
                tld_type: 1,
                whois_privacy: true,
                auto_renew_only: false,
                idn: true,
                minimum_registration: 0,
                registration_enabled: true,
                renewal_enabled: true,
                transfer_enabled: true,
                dnssec_interface_type: "ds",
                name_server_min: 2,
                name_server_max: 13,
                trustee_service_enabled: false,
                trustee_service_required: false
              }} = ReqDnsimple.Tld.get(client(200, body), "com.au")

      assert_request(:get, "/v2/tlds/com.au", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTld normalizes numeric-string bounds and preserves missing bounds" do
      string_bounds =
        tld_body()
        |> put_in(["data", "name_server_min"], "2")
        |> put_in(["data", "name_server_max"], "13")

      assert {:ok, %ReqDnsimple.Tld{name_server_min: 2, name_server_max: 13}} =
               ReqDnsimple.Tld.get(client(200, string_bounds), "com.au")

      assert_request(:get, "/v2/tlds/com.au", %{}, nil)

      missing_bounds =
        tld_body()
        |> update_in(["data"], &Map.drop(&1, ["name_server_min", "name_server_max"]))

      assert {:ok, %ReqDnsimple.Tld{name_server_min: nil, name_server_max: nil}} =
               ReqDnsimple.Tld.get(client(200, missing_bounds), "com.au")

      assert_request(:get, "/v2/tlds/com.au", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTld accepts an empty suffix and rejects invalid types before HTTP" do
      assert {:ok, %ReqDnsimple.Tld{}} = ReqDnsimple.Tld.get(client(200, tld_body()), "")
      assert_request(:get, "/v2/tlds/", %{}, nil)

      request = client(200, tld_body())

      for tld <- [nil, 1, 1.5, [], %{}] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Tld.get(request, tld)
      end

      refute_received {:request, _request}
    end

    test "getTld rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(tld_body(), ["data", "tld_type"], 4),
        put_in(tld_body(), ["data", "dnssec_interface_type"], "unsupported"),
        put_in(tld_body(), ["data", "name_server_min"], "2.5"),
        put_in(tld_body(), ["data", "whois_privacy"], 1)
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Tld.get(client(200, body), "com")

        assert_request(:get, "/v2/tlds/com", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTld preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"tld" => ["was not found"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Tld.get(client(status, body), "com")

        assert_request(:get, "/v2/tlds/com", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTld preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Tld.get(transport_error_client(:timeout), "com")
    end
  end

  describe "list_extended_attributes/2" do
    test "getTldExtendedAttributes retrieves typed definitions without pagination or a body" do
      body = extended_attributes_body()

      assert {:ok,
              [
                %ReqDnsimple.Tld.ExtendedAttribute{
                  name: "uk_legal_type",
                  description: "Legal type of the registrant",
                  required: true,
                  title: "Legal type",
                  options: [
                    %ReqDnsimple.Tld.ExtendedAttribute.Option{
                      title: "Individual",
                      value: "IND",
                      description: "A private individual"
                    }
                  ]
                },
                %ReqDnsimple.Tld.ExtendedAttribute{
                  name: "x-registry-free-text",
                  description: "",
                  required: false,
                  title: nil,
                  options: []
                }
              ]} = ReqDnsimple.Tld.list_extended_attributes(client(200, body), "co.uk")

      assert_request(:get, "/v2/tlds/co.uk/extended_attributes", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTldExtendedAttributes accepts an empty suffix and rejects invalid types before HTTP" do
      assert {:ok, []} =
               ReqDnsimple.Tld.list_extended_attributes(
                 client(200, %{"data" => []}),
                 ""
               )

      assert_request(:get, "/v2/tlds//extended_attributes", %{}, nil)

      request = client(200, %{"data" => []})

      for tld <- [nil, 1, 1.5, [], %{}] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Tld.list_extended_attributes(request, tld)
      end

      refute_received {:request, _request}
    end

    test "getTldExtendedAttributes rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(extended_attributes_body(), ["data", Access.at(0), "required"], 1),
        put_in(extended_attributes_body(), ["data", Access.at(0), "options"], nil),
        put_in(
          extended_attributes_body(),
          ["data", Access.at(0), "options", Access.at(0), "value"],
          1
        )
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Tld.list_extended_attributes(client(200, body), "com")

        assert_request(:get, "/v2/tlds/com/extended_attributes", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTldExtendedAttributes preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"tld" => ["was not found"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Tld.list_extended_attributes(client(status, body), "com")

        assert_request(:get, "/v2/tlds/com/extended_attributes", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTldExtendedAttributes preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Tld.list_extended_attributes(
                 transport_error_client(:timeout),
                 "com"
               )
    end
  end

  defp tld_body do
    %{
      "data" => %{
        "tld" => "com.au",
        "tld_type" => 1,
        "whois_privacy" => true,
        "auto_renew_only" => false,
        "idn" => true,
        "minimum_registration" => 0,
        "registration_enabled" => true,
        "renewal_enabled" => true,
        "transfer_enabled" => true,
        "dnssec_interface_type" => "ds",
        "name_server_min" => 2,
        "name_server_max" => 13,
        "trustee_service_enabled" => false,
        "trustee_service_required" => false
      }
    }
  end

  defp extended_attributes_body do
    %{
      "data" => [
        %{
          "name" => "uk_legal_type",
          "description" => "Legal type of the registrant",
          "required" => true,
          "title" => "Legal type",
          "options" => [
            %{
              "title" => "Individual",
              "value" => "IND",
              "description" => "A private individual"
            }
          ]
        },
        %{
          "name" => "x-registry-free-text",
          "description" => "",
          "required" => false,
          "options" => []
        }
      ]
    }
  end
end
