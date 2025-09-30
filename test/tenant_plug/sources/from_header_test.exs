defmodule TenantPlug.Sources.FromHeaderTest do
  use ExUnit.Case, async: true

  alias TenantPlug.Sources.FromHeader

  doctest TenantPlug.Sources.FromHeader

  describe "extract/2" do
    test "extracts tenant from default header" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-tenant-id", "header-tenant")
      
      assert FromHeader.extract(conn, []) == {:ok, "header-tenant"}
    end

    test "returns :not_found when header is missing" do
      conn = Plug.Test.conn(:get, "/")
      
      assert FromHeader.extract(conn, []) == :not_found
    end

    test "returns :not_found when header is empty" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-tenant-id", "")
      
      assert FromHeader.extract(conn, []) == :not_found
    end

    test "extracts from custom header name" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("tenant-id", "custom-header-tenant")
      
      opts = [sources: [{FromHeader, header: "tenant-id"}]]
      
      assert FromHeader.extract(conn, opts) == {:ok, "custom-header-tenant"}
    end

    test "case insensitive header matching by default" do
      # Build conn with uppercase header manually since Plug normalizes headers
      conn = %Plug.Conn{
        Plug.Test.conn(:get, "/") |
        req_headers: [{"X-TENANT-ID", "case-insensitive-tenant"}]
      }
      
      assert FromHeader.extract(conn, []) == {:ok, "case-insensitive-tenant"}
    end

    test "case sensitive header matching when enabled" do
      # Build conn with uppercase header manually 
      conn = %Plug.Conn{
        Plug.Test.conn(:get, "/") |
        req_headers: [{"X-TENANT-ID", "case-sensitive-tenant"}]
      }
      
      opts = [sources: [{FromHeader, header: "x-tenant-id", case_sensitive: true}]]
      
      assert FromHeader.extract(conn, opts) == :not_found
    end

    test "case sensitive exact match" do
      # Build conn with exact case header manually
      conn = %Plug.Conn{
        Plug.Test.conn(:get, "/") |
        req_headers: [{"X-Tenant-ID", "exact-case-tenant"}]
      }
      
      opts = [sources: [{FromHeader, header: "X-Tenant-ID", case_sensitive: true}]]
      
      assert FromHeader.extract(conn, opts) == {:ok, "exact-case-tenant"}
    end

    test "applies transform function to header value" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-tenant-id", "lowercase-tenant")
      
      opts = [sources: [{FromHeader, transform: &String.upcase/1}]]
      
      assert FromHeader.extract(conn, opts) == {:ok, "LOWERCASE-TENANT"}
    end

    test "handles transform function errors" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-tenant-id", "error-tenant")
      
      transform_fn = fn _value -> raise "Transform error" end
      opts = [sources: [{FromHeader, transform: transform_fn}]]
      
      {:error, message} = FromHeader.extract(conn, opts)
      assert String.contains?(message, "Header transformation failed")
    end

    test "uses first header value when multiple present" do
      # Manually construct headers to test multiple values
      conn = %Plug.Conn{
        Plug.Test.conn(:get, "/") | 
        req_headers: [
          {"x-tenant-id", "first-tenant"},
          {"x-tenant-id", "second-tenant"}
        ]
      }
      
      assert FromHeader.extract(conn, []) == {:ok, "first-tenant"}
    end
  end

  describe "validate_opts/1" do
    test "validates empty options" do
      assert FromHeader.validate_opts([]) == :ok
    end

    test "validates valid header option" do
      assert FromHeader.validate_opts([header: "custom-header"]) == :ok
    end

    test "rejects invalid header option" do
      assert FromHeader.validate_opts([header: 123]) == {:error, ":header must be a string"}
    end

    test "validates case_sensitive option" do
      assert FromHeader.validate_opts([case_sensitive: true]) == :ok
      assert FromHeader.validate_opts([case_sensitive: false]) == :ok
    end

    test "rejects invalid case_sensitive option" do
      assert FromHeader.validate_opts([case_sensitive: "true"]) == {:error, ":case_sensitive must be a boolean"}
    end

    test "validates transform function" do
      assert FromHeader.validate_opts([transform: &String.upcase/1]) == :ok
    end

    test "rejects invalid transform option" do
      assert FromHeader.validate_opts([transform: "not_a_function"]) == {:error, ":transform must be a function of arity 1"}
    end

    test "validates multiple options together" do
      opts = [
        header: "custom-header",
        case_sensitive: true,
        transform: &String.downcase/1
      ]
      
      assert FromHeader.validate_opts(opts) == :ok
    end
  end

  describe "default_header/0" do
    test "returns default header name" do
      assert FromHeader.default_header() == "x-tenant-id"
    end
  end

  describe "integration scenarios" do
    test "works with standard Phoenix request" do
      conn = Plug.Test.conn(:get, "/api/users")
      |> Plug.Conn.put_req_header("x-tenant-id", "api-tenant")
      |> Plug.Conn.put_req_header("authorization", "Bearer token123")
      
      assert FromHeader.extract(conn, []) == {:ok, "api-tenant"}
    end

    test "handles complex transform scenarios" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-tenant-id", "  TRIM-AND-LOWER  ")
      
      transform_fn = fn value ->
        value
        |> String.trim()
        |> String.downcase()
      end
      
      opts = [sources: [{FromHeader, transform: transform_fn}]]
      
      assert FromHeader.extract(conn, opts) == {:ok, "trim-and-lower"}
    end

    test "handles UUID tenant IDs" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-tenant-id", uuid)
      
      assert FromHeader.extract(conn, []) == {:ok, uuid}
    end

    test "handles numeric tenant IDs" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-tenant-id", "12345")
      
      assert FromHeader.extract(conn, []) == {:ok, "12345"}
    end
  end

  describe "edge cases" do
    test "handles missing sources configuration" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-tenant-id", "no-sources-tenant")
      
      # Simulate calling without sources in opts
      assert FromHeader.extract(conn, [other_option: "value"]) == {:ok, "no-sources-tenant"}
    end

    test "handles malformed sources configuration" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-tenant-id", "malformed-config-tenant")
      
      # Should still work with malformed sources config
      opts = [sources: "not-a-list"]
      assert FromHeader.extract(conn, opts) == {:ok, "malformed-config-tenant"}
    end
  end
end