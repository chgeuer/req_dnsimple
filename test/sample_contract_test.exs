defmodule ReqDnsimple.SampleContractTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @samples Path.expand("../samples", __DIR__)
  @token "dnsimple_u_offline_sample_contract"
  @environment ~w(
    DNSIMPLE_TOKEN DNSIMPLE_ACCOUNT_ID DNSIMPLE_ZONE DNSIMPLE_BASE_URL
    DNSIMPLE_RECORD_NAME_LIKE DNSIMPLE_RECORD_TYPE DNSIMPLE_ACCOUNT_IDS
    DNSIMPLE_ALLOW_MUTATIONS DNSIMPLE_TEST_ZONE
    LB_DNSIMPLE_TOKEN LB_DNSIMPLE_ACCOUNT_ID LB_DNSIMPLE_ZONE LB_DNSIMPLE_BASE_URL
  )
  @zone %{
    "id" => 100,
    "account_id" => 11,
    "name" => "sample.example.test",
    "active" => true,
    "reverse" => false,
    "secondary" => false,
    "last_transferred_at" => nil,
    "created_at" => "2026-09-01T10:00:00Z",
    "updated_at" => "2026-09-01T10:30:00Z"
  }
  @record %{
    "id" => 901,
    "zone_id" => "sample.example.test",
    "name" => "www",
    "type" => "A",
    "content" => "192.0.2.1",
    "ttl" => 60,
    "priority" => nil,
    "regions" => ["global"],
    "parent_id" => nil,
    "system_record" => false,
    "created_at" => "2026-09-01T10:00:00Z",
    "updated_at" => "2026-09-01T10:30:00Z"
  }

  setup do
    saved_environment = Map.new(@environment, &{&1, System.get_env(&1)})
    saved_options = Req.default_options()

    Enum.each(@environment, &System.delete_env/1)

    System.put_env(%{
      "DNSIMPLE_TOKEN" => @token,
      "DNSIMPLE_ACCOUNT_ID" => "11",
      "DNSIMPLE_ZONE" => "sample.example.test"
    })

    on_exit(fn ->
      Req.default_options(saved_options)

      Enum.each(saved_environment, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "every script is linked, parses, and uses existing project dependencies" do
    index = File.read!(Path.join(@samples, "README.md"))
    entry_points = Path.wildcard(Path.join(@samples, "*.exs"))

    assert length(entry_points) >= 7

    for file <- Path.wildcard(Path.join(@samples, "**/*.exs")) do
      code = File.read!(file)
      assert index =~ Path.relative_to(file, @samples)
      assert {:ok, _ast} = Code.string_to_quoted(code, file: file)
      refute code =~ "Mix.install"
      refute code =~ "IO.inspect"
      refute code =~ "token_type("
      refute code =~ "get_private_key"
      refute code =~ "hd("
    end

    notebook = File.read!(Path.join(@samples, "discover.livemd"))
    assert index =~ "discover.livemd"
    refute notebook =~ "/home/"

    for code <- notebook_cells(notebook) do
      assert {:ok, _ast} = Code.string_to_quoted(code)
      refute code =~ "IO.inspect"

      if code =~ "ReqDnsimple.new_client(" do
        assert String.ends_with?(String.trim(code), ":ok")
      end
    end
  end

  test "basic scoped reads use the existing bang and bare-list interfaces offline" do
    install_adapter(fn
      %{method: :get, path: "/v2/11/zones", query: query} ->
        {200, page([@zone], query)}

      %{method: :get, path: "/v2/11/zones/sample.example.test"} ->
        {200, %{"data" => @zone}}

      %{method: :get, path: "/v2/11/zones/sample.example.test/records", query: query} ->
        assert query["name"] == ""
        assert query["type"] == "NS"

        record =
          Map.merge(@record, %{"name" => "", "type" => "NS", "content" => "ns1.example.test"})

        {200, page([record], query)}
    end)

    output = run_sample("basic_reads.exs")
    assert output =~ "First page: 1 zones"
    assert output =~ "Zone sample.example.test: active=true"
    assert output =~ "Apex NS records: 1"

    for _ <- 1..3 do
      assert_receive {:sample_request,
                      %{method: :get, host: "api.sandbox.dnsimple.com", authorized?: true}}
    end

    refute_receive {:sample_request, _}
  end

  test "record pages and all-page enumeration preserve filters and sorting" do
    install_adapter(fn
      %{method: :get, path: "/v2/11/zones/sample.example.test/records", query: query} ->
        current_page = String.to_integer(query["page"])
        record = Map.put(@record, "id", 900 + current_page)
        {200, page([record], query, 2)}
    end)

    output = run_sample("records.exs")
    assert output =~ "Page 1/2: 1 matching records"
    assert output =~ "All pages: 2 matching records"
    refute output =~ @record["content"]

    for current_page <- ["1", "1", "2"] do
      assert_receive {:sample_request,
                      %{
                        query: %{
                          "page" => ^current_page,
                          "per_page" => "25",
                          "name_like" => "www",
                          "type" => "A",
                          "sort" => "name:asc,id:asc"
                        }
                      }}
    end

    refute_receive {:sample_request, _}
  end

  test "account discovery scopes only from the explicit whoami account identity" do
    install_adapter(fn
      %{method: :get, path: "/v2/whoami"} ->
        {200, %{"data" => %{"account" => %{"id" => 22}, "user" => nil}}}

      %{method: :get, path: "/v2/22/zones", query: query} ->
        {200, page([@zone], query)}
    end)

    assert run_sample("discover_account.exs") =~ "Account discovered through whoami"
    assert_receive {:sample_request, %{path: "/v2/whoami"}}
    assert_receive {:sample_request, %{path: "/v2/22/zones"}}
    refute_receive {:sample_request, _}
  end

  test "account discovery refuses to mistake a user identity for an account" do
    install_adapter(fn %{method: :get, path: "/v2/whoami"} ->
      {200, %{"data" => %{"account" => nil, "user" => %{"id" => 22}}}}
    end)

    assert_raise ArgumentError, ~r/whoami returned a user/, fn ->
      run_sample("discover_account.exs")
    end

    assert_receive {:sample_request, %{path: "/v2/whoami"}}
    refute_receive {:sample_request, _}
  end

  test "user discovery respects explicit selection rather than choosing the first account" do
    System.put_env("DNSIMPLE_ACCOUNT_ID", "00022")

    install_adapter(fn
      %{method: :get, path: "/v2/accounts"} ->
        {200, %{"data" => [%{"id" => 11}, %{"id" => 22}]}}

      %{method: :get, path: "/v2/22/zones", query: query} ->
        {200, page([@zone], query)}
    end)

    assert run_sample("discover_user.exs") =~ "Selected account 22"
    assert_receive {:sample_request, %{path: "/v2/accounts"}}
    assert_receive {:sample_request, %{path: "/v2/22/zones"}}
    refute_receive {:sample_request, _}
  end

  test "user discovery has no missing or unavailable account-selection fallback" do
    install_adapter(fn %{method: :get, path: "/v2/accounts"} ->
      {200, %{"data" => [%{"id" => 11}, %{"id" => 22}]}}
    end)

    for selected_id <- [nil, "99"] do
      if selected_id do
        System.put_env("DNSIMPLE_ACCOUNT_ID", selected_id)
      else
        System.delete_env("DNSIMPLE_ACCOUNT_ID")
      end

      assert_raise ArgumentError, fn -> run_sample("discover_user.exs") end
      assert_receive {:sample_request, %{path: "/v2/accounts"}}
      refute_receive {:sample_request, _}
    end
  end

  test "multiple account clients retain the shared transport and explicit account order" do
    System.put_env("DNSIMPLE_ACCOUNT_IDS", "22, 11")

    install_adapter(fn %{method: :get, path: path, query: query}
                       when path in ["/v2/22/zones", "/v2/11/zones"] ->
      {200, page([@zone], query)}
    end)

    output = run_sample("multiple_accounts.exs")
    assert output =~ "Account 22:"
    assert output =~ "Account 11:"
    assert_receive {:sample_request, %{path: "/v2/22/zones", authorized?: true}}
    assert_receive {:sample_request, %{path: "/v2/11/zones", authorized?: true}}
    refute_receive {:sample_request, _}
  end

  test "dynamic credentials rotate per request while custom transport and scope survive Req.merge" do
    System.put_env("DNSIMPLE_BASE_URL", "https://proxy.example.test/v2")
    rotated_token = "dnsimple_u_rotated_offline_sample"

    install_adapter(fn
      %{method: :get, path: "/v2/11/zones", query: query} ->
        System.put_env("DNSIMPLE_TOKEN", rotated_token)
        {200, page([@zone], query)}

      %{method: :get, path: "/v2/11/zones/sample.example.test/records", query: query} ->
        {200, page([@record], query)}
    end)

    output = run_sample("dynamic_credentials.exs")
    refute output =~ rotated_token

    for _ <- 1..2 do
      assert_receive {:sample_request,
                      %{
                        host: "proxy.example.test",
                        authorized?: true,
                        receive_timeout: 30_000,
                        example_header: ["req-dnsimple-samples"]
                      }}
    end

    refute_receive {:sample_request, _}
  end

  test "mutation consent and an explicit non-empty test zone are required before HTTP" do
    install_adapter(fn _request -> flunk("Mutation guard must prevent every HTTP request") end)
    System.put_env("DNSIMPLE_TEST_ZONE", "sample.example.test")

    for consent <- [nil, "false", "TRUE", "1"] do
      if consent do
        System.put_env("DNSIMPLE_ALLOW_MUTATIONS", consent)
      else
        System.delete_env("DNSIMPLE_ALLOW_MUTATIONS")
      end

      assert_raise ArgumentError, ~r/Mutation sample disabled/, fn ->
        run_sample("record_lifecycle.exs")
      end
    end

    System.put_env("DNSIMPLE_ALLOW_MUTATIONS", "true")

    for test_zone <- [nil, "", "   "] do
      if test_zone do
        System.put_env("DNSIMPLE_TEST_ZONE", test_zone)
      else
        System.delete_env("DNSIMPLE_TEST_ZONE")
      end

      assert_raise ArgumentError, ~r/DNSIMPLE_TEST_ZONE/, fn ->
        run_sample("record_lifecycle.exs")
      end
    end

    refute_receive {:sample_request, _}
  end

  test "record lifecycle updates and deletes only its newly created record" do
    allow_mutations()
    install_lifecycle_adapter(200, 204)

    output = run_sample("record_lifecycle.exs")
    assert output =~ "Updated and deleted only the newly created sample record 901"

    assert_receive {:sample_request,
                    %{
                      method: :post,
                      path: "/v2/11/zones/sample.example.test/records",
                      body: %{"name" => name, "type" => "TXT"}
                    }}

    assert String.starts_with?(name, "_req-dnsimple-sample-")

    assert_receive {:sample_request,
                    %{method: :patch, path: "/v2/11/zones/sample.example.test/records/901"}}

    assert_receive {:sample_request,
                    %{method: :delete, path: "/v2/11/zones/sample.example.test/records/901"}}

    refute_receive {:sample_request, _}
  end

  test "record lifecycle cleans up after an update failure and reports the original error" do
    allow_mutations()
    install_lifecycle_adapter(404, 204)

    stderr =
      capture_io(:stderr, fn ->
        error = assert_raise ReqDnsimple.Error, fn -> run_sample("record_lifecycle.exs") end
        assert error.reason == :not_found
      end)

    assert stderr =~ "Update failed; the newly created sample record was deleted"
    assert_receive {:sample_request, %{method: :post}}
    assert_receive {:sample_request, %{method: :patch}}

    assert_receive {:sample_request,
                    %{method: :delete, path: "/v2/11/zones/sample.example.test/records/901"}}

    refute_receive {:sample_request, _}
  end

  test "a cleanup failure retains both operation outcomes and identifies the new record" do
    allow_mutations()
    install_lifecycle_adapter(404, 500)

    stderr =
      capture_io(:stderr, fn ->
        error = assert_raise ReqDnsimple.Error, fn -> run_sample("record_lifecycle.exs") end

        assert {:sample_cleanup_failed,
                %{
                  record_id: 901,
                  zone: "sample.example.test",
                  operation_result: {:error, :not_found},
                  cleanup_reason: %{status: 500}
                }} = error.reason
      end)

    assert stderr =~ "Cleanup failed: check sample record 901"
    refute stderr =~ @token
    assert_receive {:sample_request, %{method: :post}}
    assert_receive {:sample_request, %{method: :patch}}
    assert_receive {:sample_request, %{method: :delete}}
    refute_receive {:sample_request, _}
  end

  test "a failed creation never triggers guessed-record deletion or an automatic retry" do
    allow_mutations()

    install_adapter(fn %{method: :post, path: "/v2/11/zones/sample.example.test/records"} ->
      {500, %{"message" => "offline failure"}}
    end)

    error = assert_raise ReqDnsimple.Error, fn -> run_sample("record_lifecycle.exs") end
    assert error.reason.status == 500
    assert_receive {:sample_request, %{method: :post}}
    refute_receive {:sample_request, _}
  end

  test "Livebook read cells execute with an offline adapter and without Mix.install" do
    notebook = File.read!(Path.join(@samples, "discover.livemd"))

    cells =
      notebook
      |> notebook_cells()
      |> Enum.reject(&String.contains?(&1, "Mix.install("))

    install_adapter(fn
      %{method: :get, path: "/v2/11/zones", query: query} ->
        {200, page([@zone], query)}

      %{method: :get, path: "/v2/11/zones/sample.example.test/records", query: query} ->
        {200, page([@record], query)}
    end)

    output =
      capture_io(fn ->
        Code.eval_string(Enum.join(cells, "\n\n"), [], file: "samples/discover.livemd")
        :ok
      end)

    refute output =~ @token

    for _ <- 1..3 do
      assert_receive {:sample_request, %{method: :get, authorized?: true}}
    end

    refute_receive {:sample_request, _}
  end

  defp run_sample(name) do
    output =
      capture_io(fn ->
        Code.eval_file(Path.join(@samples, name))
        :ok
      end)

    refute output =~ @token
    refute output =~ "%Req.Request"
    output
  end

  defp install_adapter(responder) do
    test_pid = self()

    Req.default_options(
      adapter: fn request ->
        observation = %{
          method: request.method,
          host: request.url.host,
          path: request.url.path,
          query: URI.decode_query(request.url.query || ""),
          body: if(request.body in [nil, ""], do: nil, else: Jason.decode!(request.body)),
          authorized?:
            Req.Request.get_header(request, "authorization") ==
              ["Bearer " <> System.fetch_env!("DNSIMPLE_TOKEN")],
          receive_timeout: request.options[:receive_timeout],
          example_header: Req.Request.get_header(request, "x-example-client")
        }

        send(test_pid, {:sample_request, observation})
        {status, body} = responder.(observation)
        {request, %Req.Response{status: status, body: body}}
      end,
      retry: false
    )
  end

  defp install_lifecycle_adapter(update_status, delete_status) do
    install_adapter(fn
      %{method: :post, path: "/v2/11/zones/sample.example.test/records", body: attrs} ->
        {201, %{"data" => Map.merge(@record, attrs)}}

      %{method: :patch, path: "/v2/11/zones/sample.example.test/records/901", body: attrs} ->
        {update_status, %{"data" => Map.merge(@record, attrs)}}

      %{method: :delete, path: "/v2/11/zones/sample.example.test/records/901"} ->
        {delete_status, %{}}
    end)
  end

  defp allow_mutations do
    System.put_env(%{
      "DNSIMPLE_ALLOW_MUTATIONS" => "true",
      "DNSIMPLE_TEST_ZONE" => "sample.example.test"
    })
  end

  defp page(items, query, total_pages \\ 1) do
    %{
      "data" => items,
      "pagination" => %{
        "current_page" => String.to_integer(query["page"] || "1"),
        "per_page" => String.to_integer(query["per_page"] || "30"),
        "total_entries" => total_pages * length(items),
        "total_pages" => total_pages
      }
    }
  end

  defp notebook_cells(notebook) do
    Regex.scan(~r/```elixir\n(.*?)```/s, notebook, capture: :all_but_first)
    |> List.flatten()
  end
end
