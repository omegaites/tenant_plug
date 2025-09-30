# TenantPlug

[![Hex.pm](https://img.shields.io/hexpm/v/tenant_plug.svg)](https://hex.pm/packages/tenant_plug)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/tenant_plug)
[![CI](https://github.com/Tenvia/tenant_plug/workflows/CI/badge.svg)](https://github.com/Tenvia/tenant_plug/actions)

A comprehensive Elixir Plug library for automatic tenant context management in Phoenix and Plug-based applications. TenantPlug extracts tenant information from HTTP requests using configurable sources and stores it in process-local context for easy access throughout the request lifecycle.

## Features

- 🔌 **Plug Integration**: Drop-in Plug for Phoenix endpoints and routers
- 🎯 **Multiple Extraction Sources**: Headers, subdomains, JWT tokens, and custom sources
- 📊 **Telemetry Support**: Built-in observability with comprehensive telemetry events
- 📝 **Logger Integration**: Automatic tenant metadata injection for structured logging
- 🧪 **Test Helpers**: Comprehensive testing utilities for easy integration testing
- ⚡ **Performance Focused**: Minimal overhead with efficient tenant resolution
- 🔄 **Background Job Support**: Snapshot and restore tenant context across processes
- ⚙️ **Highly Configurable**: Flexible configuration for any multi-tenant architecture

## Installation

Add `tenant_plug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tenant_plug, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Basic Header-based Tenant Extraction

```elixir
# In your Phoenix endpoint or router
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app
  
  # Add TenantPlug to extract tenant from X-Tenant-ID header
  plug TenantPlug
  
  # Your other plugs...
end
```

```elixir
# In your controllers or anywhere in the request lifecycle
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    tenant_id = TenantPlug.current()
    # tenant_id will be "acme" if request header was "X-Tenant-ID: acme"
    
    users = MyApp.Users.list_users_for_tenant(tenant_id)
    render(conn, "index.html", users: users)
  end
end
```

### 2. Multiple Extraction Sources

```elixir
# Try multiple sources in order: header, then subdomain, then JWT
plug TenantPlug,
  sources: [
    TenantPlug.Sources.FromHeader,
    TenantPlug.Sources.FromSubdomain,
    {TenantPlug.Sources.FromJWT, claim: "tenant_id"}
  ]
```

### 3. Custom Configuration

```elixir
plug TenantPlug,
  sources: [
    {TenantPlug.Sources.FromHeader, header: "x-organization-id"},
    {TenantPlug.Sources.FromSubdomain, exclude: ["www", "api", "admin"]}
  ],
  require_resolved: true,  # Halt request if no tenant found
  logger_metadata: true,   # Add tenant to log metadata
  telemetry: true         # Enable telemetry events
```

## Extraction Sources

### Header Extraction

Extract tenant ID from HTTP headers (default source):

```elixir
# Default: looks for "x-tenant-id" header
plug TenantPlug

# Custom header name
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromHeader, header: "x-organization-id"}]

# Case-sensitive header matching
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromHeader, 
             header: "X-Tenant-ID", 
             case_sensitive: true}]

# Transform header value
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromHeader, 
             transform: &String.upcase/1}]
```

**Example HTTP Request:**
```http
GET /api/users HTTP/1.1
Host: api.example.com
X-Tenant-ID: acme-corp
Authorization: Bearer ...
```

### Subdomain Extraction

Extract tenant from request subdomain:

```elixir
# Extract from first subdomain: "acme.myapp.com" -> "acme"
plug TenantPlug,
  sources: [TenantPlug.Sources.FromSubdomain]

# Custom exclusion list
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromSubdomain, 
             exclude: ["www", "api", "admin", "staging"]}]

# Extract from last subdomain: "app.acme.myapp.com" -> "acme"
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromSubdomain, position: :last}]

# Extract from specific position (0-indexed)
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromSubdomain, position: 1}]
```

**Example URLs:**
- `https://acme.myapp.com/dashboard` → tenant: `"acme"`
- `https://www.myapp.com/` → tenant: `nil` (excluded)
- `https://app.acme.myapp.com/api` → tenant: `"app"` (first) or `"acme"` (last)

### JWT Token Extraction

Extract tenant from JWT claims:

```elixir
# From Authorization header, "tenant_id" claim
plug TenantPlug,
  sources: [TenantPlug.Sources.FromJWT]

# Custom header and claim
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromJWT, 
             header: "x-auth-token",
             claim: "org_id"}]

# From cookie
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromJWT, 
             cookie: "auth_token",
             claim: "tenant"}]

# With JWT verification
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromJWT, 
             verify: true,
             secret: "your-secret-key"}]

# Nested claims with dot notation
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromJWT, 
             claim: "user.tenant_id"}]

# Transform claim value
plug TenantPlug,
  sources: [{TenantPlug.Sources.FromJWT, 
             claim: "sub",
             transform: fn sub -> 
               sub |> String.split(":") |> List.last() 
             end}]
```

**Example JWT Payload:**
```json
{
  "sub": "user-123",
  "tenant_id": "acme-corp",
  "exp": 1234567890,
  "user": {
    "tenant_id": "nested-tenant"
  }
}
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:sources` | `[module() \| {module(), keyword()}]` | `[FromHeader]` | List of extraction sources to try in order |
| `:key` | `atom()` | `:tenant_plug_tenant` | Process dictionary key for storing tenant |
| `:logger_metadata` | `boolean()` | `true` | Enable automatic logger metadata injection |
| `:telemetry` | `boolean()` | `true` | Enable telemetry events |
| `:require_resolved` | `boolean()` | `false` | Halt request (400) if no tenant is resolved |

## Usage Examples

### Phoenix Application

```elixir
# lib/my_app_web/endpoint.ex
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app
  
  # Add tenant resolution early in the plug pipeline
  plug TenantPlug,
    sources: [
      TenantPlug.Sources.FromHeader,
      TenantPlug.Sources.FromSubdomain
    ],
    require_resolved: true

  plug MyAppWeb.Router
end
```

### Router-Level Configuration

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    
    # Only resolve tenant for API routes
    plug TenantPlug,
      sources: [{TenantPlug.Sources.FromJWT, claim: "tenant_id"}]
  end

  scope "/api", MyAppWeb do
    pipe_through :api
    resources "/users", UserController
  end
end
```

### Accessing Tenant Context

```elixir
defmodule MyApp.SomeService do
  def get_data do
    case TenantPlug.current() do
      nil ->
        {:error, :no_tenant}
        
      tenant_id ->
        MyApp.Repo.all(
          from u in User, 
          where: u.tenant_id == ^tenant_id
        )
    end
  end
end
```

### Background Jobs with Tenant Context

```elixir
defmodule MyApp.EmailWorker do
  def send_welcome_email(user_id) do
    # Capture tenant context from the web request
    snapshot = TenantPlug.snapshot()
    
    Task.async(fn ->
      # Restore tenant context in background job
      TenantPlug.apply_snapshot(snapshot)
      
      # Now tenant context is available
      tenant_id = TenantPlug.current()
      user = MyApp.Users.get!(user_id, tenant_id)
      
      # Send email with tenant-specific template
      MyApp.Mailer.send_welcome_email(user, tenant_id)
    end)
  end
end
```

### GenServer with Tenant Context

```elixir
defmodule MyApp.TenantWorker do
  use GenServer
  
  def start_link(opts) do
    # Capture tenant context when starting
    snapshot = TenantPlug.snapshot()
    GenServer.start_link(__MODULE__, {opts, snapshot})
  end
  
  def init({opts, snapshot}) do
    # Restore tenant context in GenServer
    TenantPlug.apply_snapshot(snapshot)
    
    {:ok, opts}
  end
  
  def handle_call(:get_tenant_data, _from, state) do
    tenant_id = TenantPlug.current()
    data = MyApp.fetch_tenant_data(tenant_id)
    {:reply, data, state}
  end
end
```

## Logger Integration

TenantPlug automatically adds tenant information to your log metadata:

```elixir
# Configuration
config :logger, :console,
  format: "$time [$level] $metadata$message\n",
  metadata: [:tenant_id, :request_id]

# Log output will include tenant information:
# 2023-10-01T12:00:00.000Z [info] tenant_id=acme Processing user request
```

### Manual Logger Integration

```elixir
# Use logger functions directly
TenantPlug.Logger.set_metadata("manual-tenant")
Logger.info("This log will include tenant metadata")

# Temporary tenant context for logging
TenantPlug.Logger.log_with_tenant(:info, "Specific tenant log", "temp-tenant")

# Conditional logging based on tenant
if TenantPlug.Logger.present?() do
  Logger.info("Tenant-specific operation completed")
end
```

## Telemetry Integration

TenantPlug emits comprehensive telemetry events for monitoring and observability:

### Available Events

- `[:tenant_plug, :tenant, :resolved]` - Tenant successfully resolved
- `[:tenant_plug, :tenant, :cleared]` - Tenant context cleared
- `[:tenant_plug, :error, :source_exception]` - Source raised an exception
- `[:tenant_plug, :error, :source_error]` - Source returned an error
- `[:tenant_plug, :context, :snapshot_created]` - Context snapshot created
- `[:tenant_plug, :context, :snapshot_applied]` - Context snapshot applied

### Telemetry Metrics

```elixir
# In your application telemetry module
import Telemetry.Metrics

def metrics do
  [
    # Count successful tenant resolutions
    counter("tenant_plug.tenant.resolved.count"),
    
    # Monitor tenant resolution performance
    distribution("tenant_plug.tenant.resolved.duration", 
                 unit: {:native, :microsecond}),
    
    # Track tenant resolution by source
    counter("tenant_plug.tenant.resolved.count", 
            tags: [:source]),
    
    # Monitor error rates
    counter("tenant_plug.error.source_exception.count"),
    counter("tenant_plug.error.source_error.count"),
    
    # Track context snapshots (background jobs)
    counter("tenant_plug.context.snapshot_created.count"),
    counter("tenant_plug.context.snapshot_applied.count")
  ]
end
```

### Custom Telemetry Handlers

```elixir
:telemetry.attach(
  "tenant-monitoring",
  [:tenant_plug, :tenant, :resolved],
  &MyApp.TenantMonitor.handle_tenant_resolved/4,
  %{}
)

defmodule MyApp.TenantMonitor do
  def handle_tenant_resolved(event, measurements, metadata, config) do
    %{tenant: tenant_id, source: source} = metadata
    
    # Log tenant resolution
    Logger.info("Tenant resolved", 
                tenant: tenant_id, 
                source: source,
                duration: measurements.duration)
    
    # Update custom metrics
    :telemetry.execute([:my_app, :tenant, :active], %{count: 1}, metadata)
  end
end
```

## Testing

TenantPlug includes comprehensive test helpers for easy integration testing:

### Setup

```elixir
# test/support/test_helpers.ex
defmodule MyApp.TestHelpers do
  use TenantPlug.TestHelpers
  
  # TestHelpers are automatically imported and setup
end

# In your test files
defmodule MyAppWeb.UserControllerTest do
  use MyAppWeb.ConnCase
  use TenantPlug.TestHelpers
  
  # Tests here have automatic tenant context cleanup
end
```

### Basic Testing

```elixir
test "processes request with tenant context" do
  with_tenant("test-tenant") do
    assert TenantPlug.current() == "test-tenant"
    # Your test logic here
  end
  
  # Tenant context automatically cleaned up
  assert TenantPlug.current() == nil
end
```

### Phoenix Controller Testing

```elixir
test "GET /users with tenant header", %{conn: conn} do
  conn = 
    conn
    |> put_tenant_header("acme")
    |> get("/api/users")
  
  assert response(conn, 200)
  assert TenantPlug.current() == "acme"
end

test "GET /users with tenant subdomain", %{conn: conn} do
  conn = 
    conn
    |> put_tenant_subdomain("acme", "example.com")
    |> get("/api/users")
  
  assert response(conn, 200)
  assert TenantPlug.current() == "acme"
end

test "GET /users with JWT tenant", %{conn: conn} do
  conn = 
    conn
    |> put_tenant_jwt("acme", claim: "tenant_id")
    |> get("/api/users")
  
  assert response(conn, 200)
  assert TenantPlug.current() == "acme"
end
```

### Background Job Testing

```elixir
test "background job preserves tenant context" do
  set_current("job-tenant")
  snapshot = TenantPlug.snapshot()
  
  task = Task.async(fn ->
    TenantPlug.apply_snapshot(snapshot)
    TenantPlug.current()
  end)
  
  result = Task.await(task)
  assert result == "job-tenant"
end
```

### Telemetry Testing

```elixir
test "emits telemetry events on tenant resolution" do
  events = capture_telemetry_events(fn ->
    conn = 
      build_conn()
      |> put_tenant_header("telemetry-tenant")
      |> MyAppWeb.Endpoint.call([])
  end)
  
  resolved_events = Enum.filter(events, & &1.event == [:tenant_plug, :tenant, :resolved])
  assert length(resolved_events) == 1
  
  event = List.first(resolved_events)
  assert event.metadata.tenant == "telemetry-tenant"
end
```

### Assertion Helpers

```elixir
# Assert specific tenant
assert_tenant("expected-tenant")

# Assert any tenant is present
assert_tenant_present()

# Assert no tenant is set
assert_no_tenant()

# Refute specific tenant
refute_tenant("unwanted-tenant")
```

## Custom Sources

Create custom tenant extraction sources by implementing the `TenantPlug.Sources.Behaviour`:

```elixir
defmodule MyApp.CustomTenantSource do
  @behaviour TenantPlug.Sources.Behaviour

  @impl TenantPlug.Sources.Behaviour
  def extract(conn, opts) do
    case get_tenant_from_custom_logic(conn, opts) do
      nil ->
        :not_found
        
      {:error, reason} ->
        {:error, reason}
        
      tenant_id ->
        {:ok, tenant_id}
    end
  end
  
  defp get_tenant_from_custom_logic(conn, opts) do
    # Your custom extraction logic here
    # Could extract from:
    # - Custom headers
    # - Query parameters  
    # - Session data
    # - External service calls
    # - Database lookups
    # etc.
  end
end
```

Use your custom source:

```elixir
plug TenantPlug,
  sources: [
    MyApp.CustomTenantSource,
    TenantPlug.Sources.FromHeader  # Fallback
  ]
```

## Performance Considerations

TenantPlug is designed for minimal performance impact:

1. **Lazy Evaluation**: Sources are only tried until one succeeds
2. **Process Dictionary**: Uses efficient process-local storage
3. **No Network Calls**: Built-in sources don't make external requests
4. **Configurable**: Disable features you don't need (telemetry, logging)

### Benchmarking

```elixir
# Simple header extraction ~0.1μs overhead
# JWT parsing ~1-5μs overhead  
# Subdomain parsing ~0.5μs overhead
```

## Error Handling

TenantPlug handles various error scenarios gracefully:

### Source Exceptions

```elixir
# If a source raises an exception, TenantPlug:
# 1. Emits telemetry event with error details
# 2. Continues to next source in chain
# 3. Logs error if telemetry is enabled
```

### Source Errors

```elixir
# If a source returns {:error, reason}:
# 1. Emits telemetry event with error details
# 2. Stops trying sources if require_resolved: true
# 3. Continues to next source if require_resolved: false
```

### Configuration Errors

```elixir
# Invalid configuration raises ArgumentError at compile time
plug TenantPlug, sources: [NonExistentModule]  # ArgumentError
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`mix test`)
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Setup

```bash
git clone https://github.com/Tenvia/tenant_plug.git
cd tenant_plug
mix deps.get
mix test
```

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/tenant_plug_test.exs

# Run tests with specific tag
mix test --only integration
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.

## Acknowledgments

- Inspired by the need for simple, effective multi-tenancy in Elixir applications
- Built with ❤️ by the team at [Tenvia](https://tenvia.com)
- Special thanks to the Elixir community for feedback and contributions