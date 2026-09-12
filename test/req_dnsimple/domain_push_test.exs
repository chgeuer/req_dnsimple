defmodule ReqDnsimple.DomainPushTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "accept/4" do
    test "acceptPush sends one request with the selected contact and returns :ok" do
      assert :ok =
               ReqDnsimple.DomainPush.accept(
                 client(204, ""),
                 2020,
                 1,
                 contact_id: 11
               )

      assert_request(:post, "/v2/2020/pushes/1", %{}, %{contact_id: 11})
      refute_received {:request, _request}
    end

    test "acceptPush preserves explicit zero identifiers" do
      assert :ok =
               ReqDnsimple.DomainPush.accept(
                 client(204, nil),
                 0,
                 0,
                 contact_id: 0
               )

      assert_request(:post, "/v2/0/pushes/0", %{}, %{contact_id: 0})
      refute_received {:request, _request}
    end

    test "acceptPush rejects invalid path parameters and attributes before HTTP" do
      request = client(204, "")

      invalid_arguments = [
        {"2020", 1, [contact_id: 11]},
        {nil, 1, [contact_id: 11]},
        {2020, "1", [contact_id: 11]},
        {2020, nil, [contact_id: 11]},
        {2020, 1, []},
        {2020, 1, [contact_id: nil]},
        {2020, 1, [contact_id: "11"]},
        {2020, 1, [contact_id: false]},
        {2020, 1, [contact_id: ""]},
        {2020, 1, [contact_id: []]},
        {2020, 1, [contact_id: %{}]},
        {2020, 1, [contact_id: 11, unknown: true]},
        {2020, 1, %{contact_id: 11}}
      ]

      for {account_id, push_id, attrs} <- invalid_arguments do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.DomainPush.accept(request, account_id, push_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "acceptPush preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"contact_id" => ["is not eligible"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DomainPush.accept(
                   client(status, body),
                   2020,
                   1,
                   contact_id: 11
                 )

        assert_request(:post, "/v2/2020/pushes/1", %{}, %{contact_id: 11})
        refute_received {:request, _request}
      end
    end

    test "acceptPush rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DomainPush.accept(
                   client(status, body),
                   2020,
                   1,
                   contact_id: 11
                 )

        assert_request(:post, "/v2/2020/pushes/1", %{}, %{contact_id: 11})
        refute_received {:request, _request}
      end
    end

    test "acceptPush preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.DomainPush.accept(
                 transport_error_client(:timeout),
                 2020,
                 1,
                 contact_id: 11
               )
    end
  end
end
