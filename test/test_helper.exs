ExUnit.start()

# Configure test environment
Application.put_env(:logger, :level, :warn)

# Helper modules for testing
defmodule TestHelpers do
  def create_conn_with_tenant(tenant_id, method \\ :get, path \\ "/") do
    Plug.Test.conn(method, path)
    |> Plug.Conn.put_req_header("x-tenant-id", tenant_id)
  end
  
  def create_jwt_conn(claims, method \\ :get, path \\ "/") do
    token = create_test_jwt(claims)
    
    Plug.Test.conn(method, path)
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end
  
  def create_subdomain_conn(subdomain, domain \\ "example.com", method \\ :get, path \\ "/") do
    host = "#{subdomain}.#{domain}"
    
    %Plug.Conn{
      Plug.Test.conn(method, path) | 
      req_headers: [{"host", host}],
      host: host
    }
  end
  
  defp create_test_jwt(payload) do
    header = %{"alg" => "none", "typ" => "JWT"}
    
    header_encoded = encode_jwt_part(header)
    payload_encoded = encode_jwt_part(payload)
    
    "#{header_encoded}.#{payload_encoded}."
  end
  
  defp encode_jwt_part(data) do
    data
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end
end

# Test behaviour implementations for mocking
defmodule TenantPlug.Test.MockSource do
  @behaviour TenantPlug.Sources.Behaviour
  
  def extract(_conn, _opts) do
    case Process.get(:mock_source_return) do
      nil -> :not_found
      value -> value
    end
  end
end

defmodule TenantPlug.Test.ErrorSource do
  @behaviour TenantPlug.Sources.Behaviour
  
  def extract(_conn, _opts) do
    case Process.get(:error_source_return) do
      nil -> {:error, "Test error"}
      value -> value
    end
  end
end

defmodule TenantPlug.Test.ExceptionSource do
  @behaviour TenantPlug.Sources.Behaviour
  
  def extract(_conn, _opts) do
    raise "Test exception from source"
  end
end

# Global setup/teardown
ExUnit.configure(
  exclude: [:integration],
  formatters: [ExUnit.CLIFormatter]
)

# Setup function to clean tenant context between tests
defmodule TenantPlug.TestSetup do
  def setup_tenant_context(_context) do
    # Clear any existing tenant context
    TenantPlug.Context.clear()
    
    # Clear logger metadata
    Logger.metadata([])
    
    # Clear any mock configurations
    TenantPlug.TestHelpers.clear_mocks()
    
    :ok
  end
end

# Apply global setup to all test modules
ExUnit.configure(
  setup_all: [&TenantPlug.TestSetup.setup_tenant_context/1]
)