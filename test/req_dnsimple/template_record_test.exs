defmodule ReqDnsimple.TemplateRecordTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "list_page/4 and list/4" do
    test "listTemplateRecords sends ordered options once and returns typed data" do
      pagination = %{
        "current_page" => 2,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      records = [
        template_record_body(0)["data"],
        template_record_body("10")["data"] |> Map.put("id", 2)
      ]

      assert {:ok,
              {[
                 %ReqDnsimple.TemplateRecord{
                   id: 1,
                   name: "",
                   content: "mail.{{domain}}",
                   ttl: 0,
                   priority: 0
                 },
                 %ReqDnsimple.TemplateRecord{id: 2, priority: 10}
               ], ^pagination}} =
               ReqDnsimple.TemplateRecord.list_page(
                 client(200, %{"data" => records, "pagination" => pagination}),
                 1010,
                 "offline-template",
                 sort: [id: :asc, name: :desc, content: :asc, type: :desc],
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/templates/offline-template/records",
        %{
          "sort" => "id:asc,name:desc,content:asc,type:desc",
          "page" => 2,
          "per_page" => 1
        },
        nil
      )

      refute_received {:request, _request}
    end

    test "listTemplateRecords alias requests one empty page without adding defaults" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 0,
        "total_pages" => 0
      }

      assert {:ok, {[], ^pagination}} =
               ReqDnsimple.TemplateRecord.list(
                 client(200, %{"data" => [], "pagination" => pagination}),
                 0,
                 42
               )

      assert_request(:get, "/v2/0/templates/42/records", %{}, nil)
      refute_received {:request, _request}
    end

    test "listTemplateRecords accepts nullable priority and empty template identifiers" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      assert {:ok, {[%ReqDnsimple.TemplateRecord{priority: nil}], ^pagination}} =
               ReqDnsimple.TemplateRecord.list_page(
                 client(200, %{
                   "data" => [template_record_body(nil)["data"]],
                   "pagination" => pagination
                 }),
                 1010,
                 ""
               )

      assert_request(:get, "/v2/1010/templates//records", %{}, nil)
      refute_received {:request, _request}
    end

    test "listTemplateRecords rejects invalid paths and options before HTTP" do
      request =
        client(200, %{
          "data" => [],
          "pagination" => %{
            "current_page" => 1,
            "per_page" => 30,
            "total_entries" => 0,
            "total_pages" => 0
          }
        })

      invalid_calls = [
        {"1010", "offline-template", []},
        {nil, "offline-template", []},
        {1010, nil, []},
        {1010, 1.5, []},
        {1010, [], []},
        {1010, "offline-template", [:invalid]},
        {1010, "offline-template", [{:name}]},
        {1010, "offline-template", [unknown: true]},
        {1010, "offline-template", [sort: "id:asc"]},
        {1010, "offline-template", [sort: [created_at: :asc]]},
        {1010, "offline-template", [sort: [id: :sideways]]},
        {1010, "offline-template", [page: 0]},
        {1010, "offline-template", [per_page: 0]},
        {1010, "offline-template", [per_page: 101]}
      ]

      for {account_id, template, opts} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.TemplateRecord.list_page(request, account_id, template, opts)
      end

      refute_received {:request, _request}
    end

    test "listTemplateRecords preserves HTTP and transport failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.TemplateRecord.list_page(
                   client(status, body),
                   1010,
                   "offline-template"
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.TemplateRecord.list_page(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template"
               )
    end

    test "listTemplateRecords rejects malformed successful responses" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      record = template_record_body(nil)["data"]

      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => pagination},
        %{"data" => %{}, "pagination" => pagination},
        %{"data" => [Map.delete(record, "priority")], "pagination" => pagination},
        %{"data" => [Map.put(record, "priority", "+10")], "pagination" => pagination},
        %{"data" => [Map.put(record, "priority", "10\n")], "pagination" => pagination},
        %{"data" => [Map.put(record, "created_at", "invalid")], "pagination" => pagination},
        %{"data" => [record]},
        %{"data" => [record], "pagination" => nil},
        %{"data" => [record], "pagination" => Map.delete(pagination, "total_entries")},
        %{"data" => [record], "pagination" => %{pagination | "per_page" => 0}}
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.TemplateRecord.list_page(
                   client(200, body),
                   1010,
                   "offline-template"
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  describe "list_all/4" do
    test "enumerates from page one while preserving options and server order" do
      first = template_record_body(0)["data"]
      second = template_record_body(nil)["data"] |> Map.put("id", 2)

      pages = %{
        1 =>
          {200,
           %{
             "data" => [first],
             "pagination" => %{
               "current_page" => 1,
               "per_page" => 1,
               "total_entries" => 2,
               "total_pages" => 2
             }
           }},
        2 =>
          {200,
           %{
             "data" => [second],
             "pagination" => %{
               "current_page" => 2,
               "per_page" => 1,
               "total_entries" => 2,
               "total_pages" => 2
             }
           }}
      }

      assert {:ok,
              [
                %ReqDnsimple.TemplateRecord{id: 1, priority: 0},
                %ReqDnsimple.TemplateRecord{id: 2, priority: nil}
              ]} =
               ReqDnsimple.TemplateRecord.list_all(
                 page_client(pages),
                 1010,
                 "offline-template",
                 sort: [type: :desc, name: :asc],
                 per_page: 1
               )

      query = %{"sort" => "type:desc,name:asc", "per_page" => 1}

      assert_request(
        :get,
        "/v2/1010/templates/offline-template/records",
        Map.put(query, "page", 1)
      )

      assert_request(
        :get,
        "/v2/1010/templates/offline-template/records",
        Map.put(query, "page", 2)
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request =
        client(200, %{
          "data" => [],
          "pagination" => %{
            "current_page" => 1,
            "per_page" => 30,
            "total_entries" => 0,
            "total_pages" => 0
          }
        })

      assert {:error, {:invalid_option, :page}} =
               ReqDnsimple.TemplateRecord.list_all(
                 request,
                 1010,
                 "offline-template",
                 page: 2
               )

      for opts <- [[:invalid], [{:name}]] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.TemplateRecord.list_all(
                   request,
                   1010,
                   "offline-template",
                   opts
                 )
      end

      refute_received {:request, _request}
    end

    test "aborts on later-page failures and rejects non-progressing pagination" do
      first_page = %{
        "current_page" => 1,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      http_client =
        page_client(%{
          1 => {200, %{"data" => [template_record_body(0)["data"]], "pagination" => first_page}},
          2 => {503, %{"message" => "unavailable"}}
        })

      assert {:error, %{status: 503, response: %{"message" => "unavailable"}}} =
               ReqDnsimple.TemplateRecord.list_all(
                 http_client,
                 1010,
                 "offline-template"
               )

      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 1})
      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 2})

      assert {:error, {:invalid_pagination, ^first_page}} =
               ReqDnsimple.TemplateRecord.list_all(
                 page_client(%{
                   1 =>
                     {200,
                      %{
                        "data" => [template_record_body(0)["data"]],
                        "pagination" => first_page
                      }},
                   2 =>
                     {200,
                      %{
                        "data" => [template_record_body(0)["data"]],
                        "pagination" => first_page
                      }}
                 }),
                 1010,
                 "offline-template"
               )

      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 1})
      assert_request(:get, "/v2/1010/templates/offline-template/records", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "create/4" do
    test "createTemplateRecord sends all attributes once and returns the typed record" do
      assert {:ok,
              %ReqDnsimple.TemplateRecord{
                id: 1,
                template_id: 1,
                name: "",
                content: "mail.{{domain}}",
                ttl: 0,
                priority: 0,
                type: "MX",
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:00:00Z]
              }} =
               ReqDnsimple.TemplateRecord.create(
                 client(201, template_record_body(0)),
                 1010,
                 "offline-template",
                 name: "",
                 type: "MX",
                 content: "mail.{{domain}}",
                 ttl: 0,
                 priority: 0
               )

      assert_request(:post, "/v2/1010/templates/offline-template/records", %{}, %{
        "name" => "",
        "type" => "MX",
        "content" => "mail.{{domain}}",
        "ttl" => 0,
        "priority" => 0
      })

      refute_received {:request, _request}
    end

    test "createTemplateRecord preserves omitted optional attributes and path identifiers" do
      for {account_id, template} <- [{1010, 42}, {0, 0}, {1010, ""}] do
        assert {:ok, %ReqDnsimple.TemplateRecord{priority: nil}} =
                 ReqDnsimple.TemplateRecord.create(
                   client(201, template_record_body(nil)),
                   account_id,
                   template,
                   name: "",
                   type: "TXT",
                   content: "{{domain}}"
                 )

        assert_request(
          :post,
          "/v2/#{account_id}/templates/#{template}/records",
          %{},
          %{"name" => "", "type" => "TXT", "content" => "{{domain}}"}
        )

        refute_received {:request, _request}
      end
    end

    test "createTemplateRecord rejects invalid attributes before HTTP" do
      request = client(201, template_record_body(nil))
      valid = [name: "", type: "MX", content: "mail.{{domain}}"]

      invalid_calls = [
        {"1010", "offline-template", valid},
        {nil, "offline-template", valid},
        {1010, nil, valid},
        {1010, 1.5, valid},
        {1010, [], valid},
        {1010, "offline-template", [:invalid]},
        {1010, "offline-template", [{:name}]},
        {1010, "offline-template", []},
        {1010, "offline-template", Keyword.delete(valid, :name)},
        {1010, "offline-template", Keyword.delete(valid, :type)},
        {1010, "offline-template", Keyword.delete(valid, :content)},
        {1010, "offline-template", Keyword.put(valid, :name, nil)},
        {1010, "offline-template", Keyword.put(valid, :name, false)},
        {1010, "offline-template", Keyword.put(valid, :name, 0)},
        {1010, "offline-template", Keyword.put(valid, :name, [])},
        {1010, "offline-template", Keyword.put(valid, :name, %{})},
        {1010, "offline-template", Keyword.put(valid, :type, nil)},
        {1010, "offline-template", Keyword.put(valid, :type, "INVALID")},
        {1010, "offline-template", Keyword.put(valid, :content, nil)},
        {1010, "offline-template", Keyword.put(valid, :content, false)},
        {1010, "offline-template", Keyword.put(valid, :content, 0)},
        {1010, "offline-template", Keyword.put(valid, :content, [])},
        {1010, "offline-template", Keyword.put(valid, :content, %{})},
        {1010, "offline-template", Keyword.put(valid, :ttl, nil)},
        {1010, "offline-template", Keyword.put(valid, :ttl, -1)},
        {1010, "offline-template", Keyword.put(valid, :ttl, false)},
        {1010, "offline-template", Keyword.put(valid, :priority, nil)},
        {1010, "offline-template", Keyword.put(valid, :priority, false)},
        {1010, "offline-template", Keyword.put(valid, :regions, ["global"])},
        {1010, "offline-template", Keyword.put(valid, :integrated_zones, true)},
        {1010, "offline-template", Keyword.put(valid, :unknown, true)}
      ]

      for {account_id, template, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.TemplateRecord.create(request, account_id, template, attrs)
      end

      refute_received {:request, _request}
    end

    test "createTemplateRecord normalizes nullable and legacy numeric-string priorities" do
      for {wire_priority, priority} <- [{"10", 10}, {"0010", 10}, {-1, -1}, {nil, nil}] do
        assert {:ok, %ReqDnsimple.TemplateRecord{priority: ^priority}} =
                 ReqDnsimple.TemplateRecord.create(
                   client(201, template_record_body(wire_priority)),
                   1010,
                   "offline-template",
                   name: "",
                   type: "MX",
                   content: "mail.{{domain}}"
                 )

        assert_request(:post, "/v2/1010/templates/offline-template/records", %{}, %{
          "name" => "",
          "type" => "MX",
          "content" => "mail.{{domain}}"
        })

        refute_received {:request, _request}
      end
    end

    test "createTemplateRecord rejects malformed successful responses and unexpected statuses" do
      malformed_responses = [
        {201, %{}},
        {201, %{"data" => nil}},
        {201, %{"data" => %{}}},
        {201, put_in(template_record_body(nil), ["data", "created_at"], "not-a-timestamp")},
        {201, put_in(template_record_body(nil), ["data", "ttl"], -1)},
        {201, put_in(template_record_body(nil), ["data", "priority"], "high")},
        {201, put_in(template_record_body(nil), ["data", "priority"], "+10")},
        {201, put_in(template_record_body(nil), ["data", "priority"], "10\n")},
        {201, put_in(template_record_body(nil), ["data", "type"], "INVALID")},
        {200, template_record_body(nil)}
      ]

      for {status, body} <- malformed_responses do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.TemplateRecord.create(
                   client(status, body),
                   1010,
                   "offline-template",
                   name: "",
                   type: "MX",
                   content: "mail.{{domain}}"
                 )

        assert_request(:post, "/v2/1010/templates/offline-template/records", %{}, %{
          "name" => "",
          "type" => "MX",
          "content" => "mail.{{domain}}"
        })

        refute_received {:request, _request}
      end
    end

    test "createTemplateRecord preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["is invalid"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.TemplateRecord.create(
                   client(status, body),
                   1010,
                   "offline-template",
                   name: "",
                   type: "MX",
                   content: "mail.{{domain}}"
                 )

        assert_request(:post, "/v2/1010/templates/offline-template/records", %{}, %{
          "name" => "",
          "type" => "MX",
          "content" => "mail.{{domain}}"
        })

        refute_received {:request, _request}
      end
    end

    test "createTemplateRecord preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.TemplateRecord.create(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template",
                 name: "",
                 type: "MX",
                 content: "mail.{{domain}}"
               )
    end
  end

  describe "get/4" do
    test "getTemplateRecord retrieves one typed record with one bodyless request" do
      body = template_record_body(0)

      assert {:ok,
              %ReqDnsimple.TemplateRecord{
                id: 1,
                template_id: 1,
                name: "",
                content: "mail.{{domain}}",
                ttl: 0,
                priority: 0,
                type: "MX",
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:00:00Z]
              }} =
               ReqDnsimple.TemplateRecord.get(
                 client(200, body),
                 1010,
                 "offline-template",
                 1
               )

      assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getTemplateRecord normalizes legacy numeric-string and nullable priorities" do
      for {wire_priority, priority} <- [{"10", 10}, {"0010", 10}, {-1, -1}, {nil, nil}] do
        assert {:ok, %ReqDnsimple.TemplateRecord{priority: ^priority}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(200, template_record_body(wire_priority)),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord accepts integer, zero, and empty template identifiers" do
      for {account_id, template, record_id} <- [
            {1010, 42, 1},
            {0, 0, 0},
            {1010, "", 1}
          ] do
        assert {:ok, %ReqDnsimple.TemplateRecord{}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(200, template_record_body(nil)),
                   account_id,
                   template,
                   record_id
                 )

        assert_request(
          :get,
          "/v2/#{account_id}/templates/#{template}/records/#{record_id}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord rejects invalid path parameters before HTTP" do
      request = client(200, template_record_body(nil))

      for {account_id, template, record_id} <- [
            {"1010", "offline-template", 1},
            {nil, "offline-template", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "offline-template", "1"},
            {1010, "offline-template", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.TemplateRecord.get(
                   request,
                   account_id,
                   template,
                   record_id
                 )
      end

      refute_received {:request, _request}
    end

    test "getTemplateRecord rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(template_record_body(nil), ["data", "created_at"], "not-a-timestamp"),
        put_in(template_record_body(nil), ["data", "ttl"], -1),
        put_in(template_record_body(nil), ["data", "priority"], "high"),
        put_in(template_record_body(nil), ["data", "priority"], "+10"),
        put_in(template_record_body(nil), ["data", "priority"], "10\n"),
        put_in(template_record_body(nil), ["data", "type"], "INVALID")
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(200, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["was not found"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.TemplateRecord.get(
                   client(status, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(:get, "/v2/1010/templates/offline-template/records/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getTemplateRecord preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.TemplateRecord.get(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template",
                 1
               )
    end
  end

  describe "delete/4" do
    test "deleteTemplateRecord sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.TemplateRecord.delete(
                 client(204, nil),
                 1010,
                 "offline-template",
                 1
               )

      assert_request(
        :delete,
        "/v2/1010/templates/offline-template/records/1",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "deleteTemplateRecord accepts integer, zero, and empty template identifiers" do
      for {account_id, template, record_id} <- [
            {1010, 42, 1},
            {0, 0, 0},
            {1010, "", 1}
          ] do
        assert :ok =
                 ReqDnsimple.TemplateRecord.delete(
                   client(204, nil),
                   account_id,
                   template,
                   record_id
                 )

        assert_request(
          :delete,
          "/v2/#{account_id}/templates/#{template}/records/#{record_id}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "deleteTemplateRecord rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, template, record_id} <- [
            {"1010", "offline-template", 1},
            {nil, "offline-template", 1},
            {1010, nil, 1},
            {1010, 1.5, 1},
            {1010, [], 1},
            {1010, "offline-template", "1"},
            {1010, "offline-template", nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.TemplateRecord.delete(
                   request,
                   account_id,
                   template,
                   record_id
                 )
      end

      refute_received {:request, _request}
    end

    test "deleteTemplateRecord preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"template_record" => ["cannot be deleted"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.TemplateRecord.delete(
                   client(status, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(
          :delete,
          "/v2/1010/templates/offline-template/records/1",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "deleteTemplateRecord rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.TemplateRecord.delete(
                   client(status, body),
                   1010,
                   "offline-template",
                   1
                 )

        assert_request(
          :delete,
          "/v2/1010/templates/offline-template/records/1",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "deleteTemplateRecord preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.TemplateRecord.delete(
                 transport_error_client(:timeout),
                 1010,
                 "offline-template",
                 1
               )
    end
  end

  defp template_record_body(priority) do
    %{
      "data" => %{
        "id" => 1,
        "template_id" => 1,
        "name" => "",
        "content" => "mail.{{domain}}",
        "ttl" => 0,
        "priority" => priority,
        "type" => "MX",
        "created_at" => "2026-09-01T10:00:00+02:00",
        "updated_at" => "2026-09-01T10:00:00+02:00"
      }
    }
  end

  defp page_client(pages) do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:request, request})
      page = request.url.query |> URI.decode_query() |> Map.fetch!("page") |> String.to_integer()
      {status, body} = Map.fetch!(pages, page)
      {request, %Req.Response{status: status, body: body}}
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
