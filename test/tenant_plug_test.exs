defmodule TenantPlugTest do
  use ExUnit.Case, async: true
  use TenantPlug.TestHelpers

  doctest TenantPlug

  alias TenantPlug.Sources.FromHeader

  describe "init/1" do
    test "uses default options when none provided" do
      opts = TenantPlug.init([])
      
      assert opts[:sources] == [FromHeader]
      assert opts[:key] == :tenant_plug_tenant
      assert opts[:logger_metadata] == true
      assert opts[:telemetry] == true
      assert opts[:require_resolved] == false
    end

    test "merges provided options with defaults" do
      custom_opts = [
        sources: [FromHeader],
        require_resolved: true
      ]
      
      opts = TenantPlug.init(custom_opts)
      
      assert opts[:sources] == [FromHeader]
      assert opts[:require_resolved] == true
      assert opts[:logger_metadata] == true
    end

    test "validates source modules" do
      assert_raise ArgumentError, ~r/Invalid sources/, fn ->
        TenantPlug.init(sources: [NonExistentModule])
      end
    end

    test "validates key is an atom" do
      assert_raise ArgumentError, ~r/:key must be an atom/, fn ->
        TenantPlug.init(key: "invalid")
      end
    end

    test "validates boolean options" do
      assert_raise ArgumentError, ~r/:logger_metadata must be a boolean/, fn ->
        TenantPlug.init(logger_metadata: "true")
      end
    end
  end

  describe "call/2" do
    setup do
      conn = Plug.Test.conn(:get, "/test")
      opts = TenantPlug.init([])
      
      %{conn: conn, opts: opts}
    end

    test "extracts tenant from first successful source", %{conn: conn, opts: opts} do
      conn = Plug.Conn.put_req_header(conn, "x-tenant-id", "test-tenant")
      
      result_conn = TenantPlug.call(conn, opts)
      
      assert TenantPlug.current() == "test-tenant"
      assert result_conn == conn
    end

    test "continues to next source when first returns :not_found", %{conn: conn} do
      # Mock first source to return :not_found
      mock_source1 = fn _conn, _opts -> :not_found end
      mock_source2 = fn _conn, _opts -> {:ok, "from-second-source"} end
      
      # We need to create test modules that implement the behaviour
      defmodule TestSource1 do
        @behaviour TenantPlug.Sources.Behaviour
        def extract(_conn, _opts), do: :not_found
      end
      
      defmodule TestSource2 do
        @behaviour TenantPlug.Sources.Behaviour
        def extract(_conn, _opts), do: {:ok, "from-second-source"}
      end
      
      opts = TenantPlug.init(sources: [TestSource1, TestSource2])
      
      result_conn = TenantPlug.call(conn, opts)
      
      assert TenantPlug.current() == "from-second-source"
      assert result_conn == conn
    end

    test "halts request when require_resolved is true and no tenant found", %{conn: conn} do
      opts = TenantPlug.init(require_resolved: true, sources: [])
      
      result_conn = TenantPlug.call(conn, opts)
      
      assert result_conn.status == 400
      assert result_conn.halted == true
    end

    test "continues when require_resolved is false and no tenant found", %{conn: conn} do
      opts = TenantPlug.init(require_resolved: false, sources: [])
      
      result_conn = TenantPlug.call(conn, opts)
      
      assert result_conn.status == nil
      assert result_conn.halted == false
      assert TenantPlug.current() == nil
    end

    test "handles source exceptions gracefully", %{conn: conn} do
      defmodule ExceptionSource do
        @behaviour TenantPlug.Sources.Behaviour
        def extract(_conn, _opts), do: raise("Source error")
      end
      
      opts = TenantPlug.init(sources: [ExceptionSource])
      
      result_conn = TenantPlug.call(conn, opts)
      
      assert result_conn == conn
      assert TenantPlug.current() == nil
    end

    test "sets logger metadata when enabled", %{conn: conn, opts: opts} do
      conn = Plug.Conn.put_req_header(conn, "x-tenant-id", "log-tenant")
      
      TenantPlug.call(conn, opts)
      
      assert Logger.metadata()[:tenant_id] == "log-tenant"
    end

    test "skips logger metadata when disabled", %{conn: conn} do
      opts = TenantPlug.init(logger_metadata: false)
      conn = Plug.Conn.put_req_header(conn, "x-tenant-id", "no-log-tenant")
      
      TenantPlug.call(conn, opts)
      
      assert Logger.metadata()[:tenant_id] == nil
    end
  end

  describe "current/0" do
    test "returns nil when no tenant is set" do
      clear_tenant()
      assert TenantPlug.current() == nil
    end

    test "returns current tenant when set" do
      set_current("current-test-tenant")
      assert TenantPlug.current() == "current-test-tenant"
    end
  end

  describe "snapshot/0 and apply_snapshot/1" do
    test "creates and applies snapshot correctly" do
      set_current("snapshot-tenant")
      
      snapshot = TenantPlug.snapshot()
      clear_tenant()
      assert TenantPlug.current() == nil
      
      TenantPlug.apply_snapshot(snapshot)
      assert TenantPlug.current() == "snapshot-tenant"
    end

    test "handles nil snapshot" do
      TenantPlug.apply_snapshot(nil)
      assert TenantPlug.current() == nil
    end

    test "returns nil when no tenant context exists" do
      clear_tenant()
      assert TenantPlug.snapshot() == nil
    end
  end

  describe "clear/0" do
    test "clears current tenant context" do
      set_current("to-be-cleared")
      assert TenantPlug.current() == "to-be-cleared"
      
      TenantPlug.clear()
      assert TenantPlug.current() == nil
    end
  end

  describe "integration with telemetry" do
    test "emits telemetry events when enabled" do
      events = capture_telemetry_events(fn ->
        conn = 
          Plug.Test.conn(:get, "/test")
          |> Plug.Conn.put_req_header("x-tenant-id", "telemetry-tenant")
        
        opts = TenantPlug.init(telemetry: true)
        TenantPlug.call(conn, opts)
      end)
      
      assert length(events) > 0
      resolved_events = Enum.filter(events, fn event -> 
        event.event == [:tenant_plug, :tenant, :resolved]
      end)
      assert length(resolved_events) == 1
    end

    test "skips telemetry events when disabled" do
      events = capture_telemetry_events(fn ->
        conn = 
          Plug.Test.conn(:get, "/test")
          |> Plug.Conn.put_req_header("x-tenant-id", "no-telemetry-tenant")
        
        opts = TenantPlug.init(telemetry: false)
        TenantPlug.call(conn, opts)
      end)
      
      assert length(events) == 0
    end
  end

  describe "error handling" do
    test "handles source returning error" do
      defmodule ErrorSource do
        @behaviour TenantPlug.Sources.Behaviour
        def extract(_conn, _opts), do: {:error, "extraction failed"}
      end
      
      conn = Plug.Test.conn(:get, "/test")
      opts = TenantPlug.init(sources: [ErrorSource])
      
      result_conn = TenantPlug.call(conn, opts)
      
      assert result_conn == conn
      assert TenantPlug.current() == nil
    end

    test "halts on error when require_resolved is true" do
      defmodule ErrorSource do
        @behaviour TenantPlug.Sources.Behaviour
        def extract(_conn, _opts), do: {:error, "required extraction failed"}
      end
      
      conn = Plug.Test.conn(:get, "/test")
      opts = TenantPlug.init(sources: [ErrorSource], require_resolved: true)
      
      result_conn = TenantPlug.call(conn, opts)
      
      assert result_conn.status == 400
      assert result_conn.halted == true
    end
  end
end