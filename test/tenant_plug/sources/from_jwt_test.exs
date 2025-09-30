defmodule TenantPlug.Sources.FromJWTTest do
  use ExUnit.Case, async: true

  alias TenantPlug.Sources.FromJWT

  doctest TenantPlug.Sources.FromJWT

  describe "extract/2" do
    test "extracts tenant from JWT authorization header" do
      payload = %{"tenant_id" => "jwt-tenant", "exp" => future_timestamp()}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      assert FromJWT.extract(conn, []) == {:ok, "jwt-tenant"}
    end

    test "returns :not_found when authorization header missing" do
      conn = Plug.Test.conn(:get, "/")
      
      assert FromJWT.extract(conn, []) == :not_found
    end

    test "returns :not_found when bearer token missing" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Basic dXNlcjpwYXNz")
      
      assert FromJWT.extract(conn, []) == :not_found
    end

    test "extracts from custom header" do
      payload = %{"tenant_id" => "custom-header-tenant"}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("x-auth-token", token)
      
      opts = [sources: [{FromJWT, header: "x-auth-token", header_prefix: nil}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "custom-header-tenant"}
    end

    test "extracts from custom claim" do
      payload = %{"org_id" => "custom-claim-tenant"}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      opts = [sources: [{FromJWT, claim: "org_id"}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "custom-claim-tenant"}
    end

    test "extracts from cookie" do
      payload = %{"tenant_id" => "cookie-tenant"}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_resp_cookie("auth_token", token)
      |> Plug.Conn.fetch_cookies()
      
      # Manually set req_cookies since Plug.Test doesn't handle this automatically
      conn = %{conn | req_cookies: %{"auth_token" => token}}
      
      opts = [sources: [{FromJWT, cookie: "auth_token"}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "cookie-tenant"}
    end

    test "returns :not_found when claim missing" do
      payload = %{"sub" => "user123"}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      assert FromJWT.extract(conn, []) == :not_found
    end

    test "applies transform function to claim value" do
      payload = %{"tenant_id" => "lowercase-tenant"}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      opts = [sources: [{FromJWT, transform: &String.upcase/1}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "LOWERCASE-TENANT"}
    end

    test "handles transform function errors" do
      payload = %{"tenant_id" => "error-tenant"}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      transform_fn = fn _value -> raise "Transform error" end
      opts = [sources: [{FromJWT, transform: transform_fn}]]
      
      {:error, message} = FromJWT.extract(conn, opts)
      assert String.contains?(message, "JWT claim transformation failed")
    end

    test "handles nested claims with dot notation" do
      payload = %{"user" => %{"tenant_id" => "nested-tenant"}}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      opts = [sources: [{FromJWT, claim: "user.tenant_id"}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "nested-tenant"}
    end

    test "returns error for invalid JWT format" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer invalid.jwt")
      
      {:error, message} = FromJWT.extract(conn, [])
      # "invalid.jwt" decodes as base64 but produces invalid JSON
      assert String.contains?(message, "Invalid JSON in JWT payload")
    end

    test "returns error for invalid base64 encoding" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer header.!!invalid_base64!!.signature")
      
      {:error, message} = FromJWT.extract(conn, [])
      assert String.contains?(message, "Invalid base64 encoding")
    end

    test "returns error for invalid JSON in payload" do
      header = Base.url_encode64(~s({"alg":"none"}), padding: false)
      payload = Base.url_encode64("invalid json", padding: false)
      token = "#{header}.#{payload}."
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      {:error, message} = FromJWT.extract(conn, [])
      assert String.contains?(message, "Invalid JSON")
    end

    test "handles JWT with custom prefix" do
      payload = %{"tenant_id" => "custom-prefix-tenant"}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Token #{token}")
      
      opts = [sources: [{FromJWT, header_prefix: "Token "}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "custom-prefix-tenant"}
    end

    test "handles JWT without prefix" do
      payload = %{"tenant_id" => "no-prefix-tenant"}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", token)
      
      opts = [sources: [{FromJWT, header_prefix: nil}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "no-prefix-tenant"}
    end
  end

  describe "validate_opts/1" do
    test "validates empty options" do
      assert FromJWT.validate_opts([]) == :ok
    end

    test "validates header option" do
      assert FromJWT.validate_opts([header: "x-auth"]) == :ok
    end

    test "rejects invalid header option" do
      assert FromJWT.validate_opts([header: 123]) == {:error, ":header must be a string"}
    end

    test "validates header_prefix option" do
      assert FromJWT.validate_opts([header_prefix: "Token "]) == :ok
    end

    test "rejects invalid header_prefix option" do
      assert FromJWT.validate_opts([header_prefix: 123]) == {:error, ":header_prefix must be a string"}
    end

    test "validates cookie option" do
      assert FromJWT.validate_opts([cookie: "auth_token"]) == :ok
    end

    test "rejects invalid cookie option" do
      assert FromJWT.validate_opts([cookie: 123]) == {:error, ":cookie must be a string"}
    end

    test "validates claim option" do
      assert FromJWT.validate_opts([claim: "org_id"]) == :ok
    end

    test "rejects invalid claim option" do
      assert FromJWT.validate_opts([claim: 123]) == {:error, ":claim must be a string"}
    end

    test "validates verify without secret" do
      assert FromJWT.validate_opts([verify: false]) == :ok
    end

    test "validates verify with secret" do
      assert FromJWT.validate_opts([verify: true, secret: "secret-key"]) == :ok
    end

    test "rejects verify true without secret" do
      assert FromJWT.validate_opts([verify: true]) == {:error, ":secret is required when :verify is true"}
    end

    test "validates transform function" do
      assert FromJWT.validate_opts([transform: &String.upcase/1]) == :ok
    end

    test "rejects invalid transform" do
      assert FromJWT.validate_opts([transform: "not_function"]) == {:error, ":transform must be a function of arity 1"}
    end
  end

  describe "default_header/0" do
    test "returns default header name" do
      assert FromJWT.default_header() == "authorization"
    end
  end

  describe "default_claim/0" do
    test "returns default claim name" do
      assert FromJWT.default_claim() == "tenant_id"
    end
  end

  describe "integration scenarios" do
    test "Auth0 style JWT" do
      payload = %{
        "sub" => "auth0|user123",
        "tenant_id" => "auth0-tenant",
        "iat" => past_timestamp(),
        "exp" => future_timestamp()
      }
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/api/users")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      assert FromJWT.extract(conn, []) == {:ok, "auth0-tenant"}
    end

    test "Firebase JWT with custom claims" do
      payload = %{
        "iss" => "https://securetoken.google.com/project-id",
        "aud" => "project-id", 
        "auth_time" => past_timestamp(),
        "user_id" => "firebase-user-123",
        "sub" => "firebase-user-123",
        "iat" => past_timestamp(),
        "exp" => future_timestamp(),
        "firebase" => %{
          "identities" => %{},
          "sign_in_provider" => "custom"
        },
        "org_id" => "firebase-org"
      }
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      opts = [sources: [{FromJWT, claim: "org_id"}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "firebase-org"}
    end

    test "microservice JWT with tenant in subject" do
      payload = %{
        "sub" => "tenant:acme:user:123",
        "iat" => past_timestamp(),
        "exp" => future_timestamp()
      }
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      # Extract tenant from subject using transform
      transform_fn = fn sub ->
        sub
        |> String.split(":")
        |> Enum.at(1)
      end
      
      opts = [sources: [{FromJWT, claim: "sub", transform: transform_fn}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "acme"}
    end
  end

  describe "edge cases" do
    test "handles empty token" do
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer ")
      
      assert FromJWT.extract(conn, []) == :not_found
    end

    test "handles whitespace in token" do
      payload = %{"tenant_id" => "whitespace-tenant"}
      token = "  #{create_test_jwt(payload)}  "
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer#{token}")
      
      opts = [sources: [{FromJWT, header_prefix: "Bearer"}]]
      
      assert FromJWT.extract(conn, opts) == {:ok, "whitespace-tenant"}
    end

    test "handles missing configuration gracefully" do
      payload = %{"tenant_id" => "config-tenant"}
      token = create_test_jwt(payload)
      
      conn = Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      
      # Should work with empty opts
      assert FromJWT.extract(conn, [other_option: "value"]) == {:ok, "config-tenant"}
    end
  end

  # Helper functions
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

  defp future_timestamp do
    System.system_time(:second) + 3600
  end

  defp past_timestamp do
    System.system_time(:second) - 3600
  end
end