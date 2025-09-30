defmodule TenantPlug.TestHelpers do
  @moduledoc """
  Test helpers for TenantPlug integration testing.

  This module provides utilities to simplify testing applications that use TenantPlug.
  It includes functions to set up tenant context, mock tenant extraction, and verify
  tenant-related behavior in tests.

  ## Usage

      # In your test file
      use ExUnit.Case
      import TenantPlug.TestHelpers

      test "processes request with tenant context" do
        with_tenant("test-tenant") do
          assert TenantPlug.current() == "test-tenant"
          # Your test logic here
        end
      end

  ## Setup in test_helper.exs

      # Optional: Automatically clear tenant context between tests
      ExUnit.start()

      ExUnit.configure(
        before_each: fn _tags ->
          TenantPlug.TestHelpers.clear_tenant()
          :ok
        end
      )

  ## Phoenix Controller Testing

      import TenantPlug.TestHelpers

      test "GET /api/users with tenant", %{conn: conn} do
        conn = 
          conn
          |> put_tenant_header("acme")
          |> get("/api/users")
        
        assert response(conn, 200)
        assert TenantPlug.current() == "acme"
      end

  ## Background Job Testing

      test "background job preserves tenant context" do
        set_current("job-tenant")
        snapshot = TenantPlug.snapshot()
        
        Task.async(fn ->
          TenantPlug.apply_snapshot(snapshot)
          assert TenantPlug.current() == "job-tenant"
        end)
        |> Task.await()
      end
  """

  alias TenantPlug.Context

  @doc """
  Set the current tenant for testing.

  This directly sets the tenant in the process context without going through
  the normal extraction process.

  ## Examples

      iex> TenantPlug.TestHelpers.set_current("test-tenant")
      :ok
      iex> TenantPlug.current()
      "test-tenant"
  """
  @spec set_current(term()) :: :ok
  def set_current(tenant) do
    Context.set(tenant)
  end

  @doc """
  Clear the current tenant context.

  Useful for cleaning up between tests or ensuring a clean state.

  ## Examples

      iex> TenantPlug.TestHelpers.set_current("test-tenant")
      iex> TenantPlug.TestHelpers.clear_tenant()
      :ok
      iex> TenantPlug.current()
      nil
  """
  @spec clear_tenant() :: :ok
  def clear_tenant do
    Context.clear()
  end

  @doc """
  Execute a function with a specific tenant context.

  The tenant context is automatically cleaned up after the function executes,
  even if an exception is raised.

  ## Examples

      TenantPlug.TestHelpers.with_tenant("test-tenant", fn ->
        assert TenantPlug.current() == "test-tenant"
        # Your test logic here
      end)

      # Tenant context is automatically cleared after the block
      assert TenantPlug.current() == nil
  """
  @spec with_tenant(term(), fun()) :: term()
  def with_tenant(tenant, fun) when is_function(fun, 0) do
    Context.with_tenant(tenant, fun)
  end

  @doc """
  Add tenant header to a Plug.Conn for testing.

  ## Examples

      conn = 
        build_conn()
        |> TenantPlug.TestHelpers.put_tenant_header("test-tenant")
        |> get("/api/endpoint")
  """
  @spec put_tenant_header(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  def put_tenant_header(conn, tenant, header_name \\ "x-tenant-id") do
    Plug.Conn.put_req_header(conn, header_name, tenant)
  end

  @doc """
  Add tenant to subdomain in conn host for testing.

  ## Examples

      conn = 
        build_conn()
        |> TenantPlug.TestHelpers.put_tenant_subdomain("acme", "myapp.com")
        |> get("/api/endpoint")
  """
  @spec put_tenant_subdomain(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  def put_tenant_subdomain(conn, tenant, base_domain) do
    host = "#{tenant}.#{base_domain}"
    %{conn | host: host, req_headers: [{"host", host} | conn.req_headers]}
  end

  @doc """
  Add JWT token with tenant claim to authorization header for testing.

  ## Examples

      # Simple unverified JWT
      conn = 
        build_conn()
        |> TenantPlug.TestHelpers.put_tenant_jwt("test-tenant")
        |> get("/api/endpoint")

      # Custom claim and header
      conn = 
        build_conn()
        |> TenantPlug.TestHelpers.put_tenant_jwt("acme", claim: "org_id", header: "x-auth")
        |> get("/api/endpoint")
  """
  @spec put_tenant_jwt(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  def put_tenant_jwt(conn, tenant, opts \\ []) do
    claim = opts[:claim] || "tenant_id"
    header = opts[:header] || "authorization"
    prefix = opts[:prefix] || "Bearer "
    
    payload = %{claim => tenant, "exp" => System.system_time(:second) + 3600}
    token = create_test_jwt(payload)
    
    header_value = if prefix, do: prefix <> token, else: token
    
    Plug.Conn.put_req_header(conn, header, header_value)
  end

  @doc """
  Create a test JWT token with the given payload.

  Note: This creates an unverified JWT for testing purposes only.

  ## Examples

      iex> token = TenantPlug.TestHelpers.create_test_jwt(%{"tenant_id" => "test"})
      iex> is_binary(token)
      true
  """
  @spec create_test_jwt(map()) :: String.t()
  def create_test_jwt(payload) do
    header = %{"alg" => "none", "typ" => "JWT"}
    
    header_encoded = encode_jwt_part(header)
    payload_encoded = encode_jwt_part(payload)
    
    "#{header_encoded}.#{payload_encoded}."
  end

  @doc """
  Assert that the current tenant matches the expected value.

  ## Examples

      TenantPlug.TestHelpers.assert_tenant("expected-tenant")
      TenantPlug.TestHelpers.assert_tenant(nil)  # Assert no tenant is set
  """
  @spec assert_tenant(term()) :: :ok
  def assert_tenant(expected_tenant) do
    actual_tenant = TenantPlug.current()
    
    if actual_tenant == expected_tenant do
      :ok
    else
      raise ExUnit.AssertionError,
        message: "Expected tenant to be #{inspect(expected_tenant)}, got #{inspect(actual_tenant)}"
    end
  end

  @doc """
  Refute that the current tenant matches the given value.

  ## Examples

      TenantPlug.TestHelpers.refute_tenant("unwanted-tenant")
  """
  @spec refute_tenant(term()) :: :ok
  def refute_tenant(unwanted_tenant) do
    actual_tenant = TenantPlug.current()
    
    if actual_tenant != unwanted_tenant do
      :ok
    else
      raise ExUnit.AssertionError,
        message: "Expected tenant not to be #{inspect(unwanted_tenant)}"
    end
  end

  @doc """
  Assert that a tenant is currently set (any non-nil value).

  ## Examples

      TenantPlug.TestHelpers.assert_tenant_present()
  """
  @spec assert_tenant_present() :: :ok
  def assert_tenant_present do
    case TenantPlug.current() do
      nil ->
        raise ExUnit.AssertionError, message: "Expected tenant to be present, but none was set"
      _ ->
        :ok
    end
  end

  @doc """
  Assert that no tenant is currently set.

  ## Examples

      TenantPlug.TestHelpers.assert_no_tenant()
  """
  @spec assert_no_tenant() :: :ok
  def assert_no_tenant do
    case TenantPlug.current() do
      nil ->
        :ok
      tenant ->
        raise ExUnit.AssertionError, 
          message: "Expected no tenant to be set, but found #{inspect(tenant)}"
    end
  end

  @doc """
  Mock a tenant source to always return a specific tenant.

  This is useful for testing specific scenarios without setting up real headers,
  subdomains, or JWT tokens.

  ## Examples

      # Mock header source to return specific tenant
      TenantPlug.TestHelpers.mock_source(
        TenantPlug.Sources.FromHeader, 
        "mocked-tenant"
      )

      # Mock source to return an error
      TenantPlug.TestHelpers.mock_source(
        TenantPlug.Sources.FromHeader, 
        {:error, "Invalid tenant"}
      )
  """
  @spec mock_source(module(), term()) :: :ok
  def mock_source(source_module, return_value) do
    if Code.ensure_loaded?(Mox) do
      # If Mox is available, use it for mocking
      mock_name = Module.concat([source_module, "Mock"])
      
      Mox.defmock(mock_name, for: TenantPlug.Sources.Behaviour)
      Mox.expect(mock_name, :extract, fn _conn, _opts -> return_value end)
      
      # Store mock reference for cleanup
      Process.put({:tenant_plug_mock, source_module}, mock_name)
    else
      # Simple process-based mock
      Process.put({:tenant_plug_mock, source_module}, return_value)
    end
    
    :ok
  end

  @doc """
  Clear all mocked sources.

  ## Examples

      TenantPlug.TestHelpers.clear_mocks()
  """
  @spec clear_mocks() :: :ok
  def clear_mocks do
    Process.get()
    |> Enum.filter(fn
      {{:tenant_plug_mock, _}, _} -> true
      _ -> false
    end)
    |> Enum.each(fn {key, _} -> Process.delete(key) end)
    
    :ok
  end

  @doc """
  Create a test snapshot with specific tenant data.

  ## Examples

      snapshot = TenantPlug.TestHelpers.create_test_snapshot("test-tenant")
      TenantPlug.apply_snapshot(snapshot)
      assert TenantPlug.current() == "test-tenant"
  """
  @spec create_test_snapshot(term()) :: map()
  def create_test_snapshot(tenant) do
    %{tenant_plug_tenant: tenant}
  end

  @doc """
  Capture telemetry events during test execution.

  ## Examples

      events = TenantPlug.TestHelpers.capture_telemetry_events(fn ->
        # Code that triggers telemetry events
        TenantPlug.TestHelpers.set_current("test-tenant")
      end)
      
      assert length(events) > 0
  """
  @spec capture_telemetry_events(fun()) :: [map()]
  def capture_telemetry_events(fun) when is_function(fun, 0) do
    test_pid = self()
    handler_id = "test_handler_#{:erlang.unique_integer()}"
    
    # Flush any existing messages from previous handlers
    flush_telemetry_messages()
    
    handler = fn event, measurements, metadata, _config ->
      send(test_pid, {:telemetry_event, event, measurements, metadata})
    end
    
    :telemetry.attach_many(
      handler_id,
      TenantPlug.Telemetry.events(),
      handler,
      %{}
    )
    
    try do
      fun.()
      collect_telemetry_events([])
    after
      :telemetry.detach(handler_id)
    end
  end

  # Private helper functions

  defp flush_telemetry_messages do
    receive do
      {:telemetry_event, _, _, _} -> flush_telemetry_messages()
    after
      0 -> :ok
    end
  end

  defp encode_jwt_part(data) do
    data
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp collect_telemetry_events(acc) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        event_data = %{
          event: event,
          measurements: measurements,
          metadata: metadata
        }
        collect_telemetry_events([event_data | acc])
    after
      10 -> Enum.reverse(acc)
    end
  end

  @doc """
  Setup macro for including test helpers in ExUnit test modules.

  ## Examples

      defmodule MyAppTest do
        use ExUnit.Case
        use TenantPlug.TestHelpers

        test "my test" do
          with_tenant("test-tenant") do
            # Test code here
          end
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      import TenantPlug.TestHelpers
      
      setup do
        TenantPlug.TestHelpers.clear_tenant()
        TenantPlug.TestHelpers.clear_mocks()
        :ok
      end
    end
  end
end