defmodule TenantPlug.Sources.FromSubdomainTest do
  use ExUnit.Case, async: true

  alias TenantPlug.Sources.FromSubdomain

  doctest TenantPlug.Sources.FromSubdomain

  describe "extract/2" do
    test "extracts tenant from subdomain" do
      conn = conn_with_host("acme.example.com")
      
      assert FromSubdomain.extract(conn, []) == {:ok, "acme"}
    end

    test "returns :not_found for excluded subdomains" do
      conn = conn_with_host("www.example.com")
      
      assert FromSubdomain.extract(conn, []) == :not_found
    end

    test "returns :not_found when no subdomain present" do
      conn = conn_with_host("example.com")
      
      assert FromSubdomain.extract(conn, []) == :not_found
    end

    test "returns :not_found for insufficient domain parts" do
      conn = conn_with_host("localhost")
      
      assert FromSubdomain.extract(conn, []) == :not_found
    end

    test "extracts with custom exclusion list" do
      conn = conn_with_host("staging.example.com")
      opts = [sources: [{FromSubdomain, exclude: ["www", "api"]}]]
      
      assert FromSubdomain.extract(conn, opts) == {:ok, "staging"}
    end

    test "respects custom exclusion list" do
      conn = conn_with_host("staging.example.com")
      opts = [sources: [{FromSubdomain, exclude: ["www", "api", "staging"]}]]
      
      assert FromSubdomain.extract(conn, opts) == :not_found
    end

    test "extracts first subdomain by default" do
      conn = conn_with_host("app.tenant.example.com")
      
      assert FromSubdomain.extract(conn, []) == {:ok, "app"}
    end

    test "extracts last subdomain when configured" do
      conn = conn_with_host("app.tenant.example.com")
      opts = [sources: [{FromSubdomain, position: :last}]]
      
      assert FromSubdomain.extract(conn, opts) == {:ok, "tenant"}
    end

    test "extracts subdomain at specific position" do
      conn = conn_with_host("first.second.third.example.com")
      opts = [sources: [{FromSubdomain, position: 1}]]
      
      assert FromSubdomain.extract(conn, opts) == {:ok, "second"}
    end

    test "returns :not_found for invalid position" do
      conn = conn_with_host("only.example.com")
      opts = [sources: [{FromSubdomain, position: 5}]]
      
      assert FromSubdomain.extract(conn, opts) == :not_found
    end

    test "applies transform function" do
      conn = conn_with_host("lowercase.example.com")
      opts = [sources: [{FromSubdomain, transform: &String.upcase/1}]]
      
      assert FromSubdomain.extract(conn, opts) == {:ok, "LOWERCASE"}
    end

    test "handles transform function errors" do
      conn = conn_with_host("error.example.com")
      transform_fn = fn _value -> raise "Transform error" end
      opts = [sources: [{FromSubdomain, transform: transform_fn}]]
      
      {:error, message} = FromSubdomain.extract(conn, opts)
      assert String.contains?(message, "Subdomain transformation failed")
    end

    test "respects custom min_parts setting" do
      conn = conn_with_host("sub.domain.tld")
      opts = [sources: [{FromSubdomain, min_parts: 4}]]
      
      assert FromSubdomain.extract(conn, opts) == :not_found
    end

    test "allows lower min_parts setting" do
      conn = conn_with_host("sub.domain.tld")
      opts = [sources: [{FromSubdomain, min_parts: 2}]]
      
      assert FromSubdomain.extract(conn, opts) == {:ok, "sub"}
    end

    test "handles missing host header" do
      conn = Plug.Test.conn(:get, "/")
      
      assert FromSubdomain.extract(conn, []) == :not_found
    end

    test "handles empty host header" do
      conn = %Plug.Conn{
        Plug.Test.conn(:get, "/") | 
        req_headers: [{"host", ""}]
      }
      
      assert FromSubdomain.extract(conn, []) == :not_found
    end

    test "strips port from host header" do
      conn = conn_with_host("tenant.example.com:8080")
      
      assert FromSubdomain.extract(conn, []) == {:ok, "tenant"}
    end
  end

  describe "validate_opts/1" do
    test "validates empty options" do
      assert FromSubdomain.validate_opts([]) == :ok
    end

    test "validates exclude list" do
      assert FromSubdomain.validate_opts([exclude: ["www", "api"]]) == :ok
    end

    test "rejects invalid exclude list" do
      assert FromSubdomain.validate_opts([exclude: "www"]) == {:error, ":exclude must be a list of strings"}
      assert FromSubdomain.validate_opts([exclude: [123, "www"]]) == {:error, ":exclude must be a list of strings"}
    end

    test "validates position options" do
      assert FromSubdomain.validate_opts([position: :first]) == :ok
      assert FromSubdomain.validate_opts([position: :last]) == :ok
      assert FromSubdomain.validate_opts([position: 0]) == :ok
      assert FromSubdomain.validate_opts([position: 5]) == :ok
    end

    test "rejects invalid position options" do
      assert FromSubdomain.validate_opts([position: -1]) == {:error, ":position must be :first, :last, or a non-negative integer"}
      assert FromSubdomain.validate_opts([position: "first"]) == {:error, ":position must be :first, :last, or a non-negative integer"}
    end

    test "validates transform function" do
      assert FromSubdomain.validate_opts([transform: &String.upcase/1]) == :ok
    end

    test "rejects invalid transform" do
      assert FromSubdomain.validate_opts([transform: "not_function"]) == {:error, ":transform must be a function of arity 1"}
    end

    test "validates min_parts" do
      assert FromSubdomain.validate_opts([min_parts: 2]) == :ok
      assert FromSubdomain.validate_opts([min_parts: 5]) == :ok
    end

    test "rejects invalid min_parts" do
      assert FromSubdomain.validate_opts([min_parts: 1]) == {:error, ":min_parts must be an integer >= 2"}
      assert FromSubdomain.validate_opts([min_parts: "3"]) == {:error, ":min_parts must be an integer >= 2"}
    end
  end

  describe "default_excludes/0" do
    test "returns default exclusion list" do
      assert FromSubdomain.default_excludes() == ["www", "api", "admin"]
    end
  end

  describe "parse_host/1" do
    test "parses simple domain" do
      assert FromSubdomain.parse_host("example.com") == 
        {:ok, %{subdomain: nil, domain: "example", tld: "com"}}
    end

    test "parses domain with subdomain" do
      assert FromSubdomain.parse_host("tenant.example.com") == 
        {:ok, %{subdomain: "tenant", domain: "example", tld: "com"}}
    end

    test "parses complex subdomain" do
      assert FromSubdomain.parse_host("app.tenant.service.example.com") == 
        {:ok, %{subdomain: "app.tenant.service", domain: "example", tld: "com"}}
    end

    test "handles invalid host format" do
      assert FromSubdomain.parse_host("invalid") == {:error, "Invalid host format"}
    end
  end

  describe "integration scenarios" do
    test "multi-tenant SaaS application" do
      # Customer subdomain
      conn = conn_with_host("acme-corp.myapp.com")
      assert FromSubdomain.extract(conn, []) == {:ok, "acme-corp"}
      
      # Admin interface should be excluded
      conn = conn_with_host("admin.myapp.com")
      assert FromSubdomain.extract(conn, []) == :not_found
    end

    test "environment-specific deployment" do
      conn = conn_with_host("tenant.staging.myapp.com")
      opts = [sources: [{FromSubdomain, position: :last, exclude: ["staging"]}]]
      
      # Should extract "tenant" as the last non-excluded subdomain
      assert FromSubdomain.extract(conn, opts) == {:ok, "tenant"}
    end

    test "UUID-based tenant identifiers" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      conn = conn_with_host("#{uuid}.example.com")
      
      assert FromSubdomain.extract(conn, []) == {:ok, uuid}
    end

    test "numeric tenant identifiers" do
      conn = conn_with_host("12345.example.com")
      
      assert FromSubdomain.extract(conn, []) == {:ok, "12345"}
    end
  end

  describe "edge cases" do
    test "handles international domain names" do
      conn = conn_with_host("tenant.münchen.de")
      
      assert FromSubdomain.extract(conn, []) == {:ok, "tenant"}
    end

    test "handles hyphenated subdomains" do
      conn = conn_with_host("my-tenant.example.com")
      
      assert FromSubdomain.extract(conn, []) == {:ok, "my-tenant"}
    end

    test "handles numeric domains" do
      conn = conn_with_host("tenant.192.168.1.1")
      
      # Should still work with IP addresses
      assert FromSubdomain.extract(conn, []) == {:ok, "tenant"}
    end

    test "case sensitivity in subdomains" do
      conn = conn_with_host("UPPERCASE.example.com")
      
      # Should preserve case
      assert FromSubdomain.extract(conn, []) == {:ok, "UPPERCASE"}
    end
  end

  # Helper function to create conn with specific host
  defp conn_with_host(host) do
    %Plug.Conn{
      Plug.Test.conn(:get, "/") | 
      req_headers: [{"host", host}]
    }
  end
end