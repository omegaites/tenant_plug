defmodule TenantPlug.TestHelpersTest do
  use ExUnit.Case, async: true
  use TenantPlug.TestHelpers

  alias TenantPlug.TestHelpers

  describe "set_current/1 and clear_tenant/0" do
    test "sets and clears current tenant" do
      TestHelpers.set_current("helper-tenant")
      assert TenantPlug.current() == "helper-tenant"
      
      TestHelpers.clear_tenant()
      assert TenantPlug.current() == nil
    end
  end

  describe "with_tenant/2" do
    test "executes function with temporary tenant" do
      result = TestHelpers.with_tenant("temp-tenant", fn ->
        assert TenantPlug.current() == "temp-tenant"
        "result"
      end)
      
      assert result == "result"
      assert TenantPlug.current() == nil
    end

    test "restores previous tenant after execution" do
      TestHelpers.set_current("original-tenant")
      
      TestHelpers.with_tenant("temp-tenant", fn ->
        assert TenantPlug.current() == "temp-tenant"
      end)
      
      assert TenantPlug.current() == "original-tenant"
    end

    test "restores context after exception" do
      TestHelpers.set_current("exception-original")
      
      assert_raise RuntimeError, fn ->
        TestHelpers.with_tenant("exception-temp", fn ->
          raise "Test exception"
        end)
      end
      
      assert TenantPlug.current() == "exception-original"
    end
  end

  describe "put_tenant_header/3" do
    test "adds tenant header to connection" do
      conn = Plug.Test.conn(:get, "/")
      |> TestHelpers.put_tenant_header("header-tenant")
      
      assert Plug.Conn.get_req_header(conn, "x-tenant-id") == ["header-tenant"]
    end

    test "adds custom header to connection" do
      conn = Plug.Test.conn(:get, "/")
      |> TestHelpers.put_tenant_header("custom-tenant", "tenant-header")
      
      assert Plug.Conn.get_req_header(conn, "tenant-header") == ["custom-tenant"]
    end
  end

  describe "put_tenant_subdomain/3" do
    test "sets tenant subdomain in host" do
      conn = Plug.Test.conn(:get, "/")
      |> TestHelpers.put_tenant_subdomain("subdomain-tenant", "example.com")
      
      assert conn.host == "subdomain-tenant.example.com"
      assert Plug.Conn.get_req_header(conn, "host") == ["subdomain-tenant.example.com"]
    end
  end

  describe "put_tenant_jwt/3" do
    test "adds JWT with tenant claim to authorization header" do
      conn = Plug.Test.conn(:get, "/")
      |> TestHelpers.put_tenant_jwt("jwt-tenant")
      
      [auth_header] = Plug.Conn.get_req_header(conn, "authorization")
      assert String.starts_with?(auth_header, "Bearer ")
      
      # Extract and verify the JWT contains the tenant
      token = String.replace_prefix(auth_header, "Bearer ", "")
      assert token_contains_claim?(token, "tenant_id", "jwt-tenant")
    end

    test "adds JWT with custom claim" do
      conn = Plug.Test.conn(:get, "/")
      |> TestHelpers.put_tenant_jwt("custom-tenant", claim: "org_id")
      
      [auth_header] = Plug.Conn.get_req_header(conn, "authorization")
      token = String.replace_prefix(auth_header, "Bearer ", "")
      assert token_contains_claim?(token, "org_id", "custom-tenant")
    end

    test "adds JWT to custom header" do
      conn = Plug.Test.conn(:get, "/")
      |> TestHelpers.put_tenant_jwt("custom-header-tenant", header: "x-auth", prefix: "Token ")
      
      [header_value] = Plug.Conn.get_req_header(conn, "x-auth")
      assert String.starts_with?(header_value, "Token ")
    end
  end

  describe "create_test_jwt/1" do
    test "creates valid JWT with payload" do
      payload = %{"tenant_id" => "test-tenant", "exp" => 1234567890}
      token = TestHelpers.create_test_jwt(payload)
      
      assert is_binary(token)
      assert String.contains?(token, ".")
      assert token_contains_claim?(token, "tenant_id", "test-tenant")
    end

    test "creates JWT with complex payload" do
      payload = %{
        "tenant_id" => "complex-tenant",
        "user" => %{"id" => 123, "role" => "admin"},
        "scopes" => ["read", "write"]
      }
      
      token = TestHelpers.create_test_jwt(payload)
      assert token_contains_claim?(token, "tenant_id", "complex-tenant")
    end
  end

  describe "assert_tenant/1" do
    test "passes when tenant matches" do
      TestHelpers.set_current("assert-tenant")
      TestHelpers.assert_tenant("assert-tenant")
    end

    test "passes when both are nil" do
      TestHelpers.clear_tenant()
      TestHelpers.assert_tenant(nil)
    end

    test "fails when tenant doesn't match" do
      TestHelpers.set_current("wrong-tenant")
      
      assert_raise ExUnit.AssertionError, ~r/Expected tenant to be "expected"/, fn ->
        TestHelpers.assert_tenant("expected")
      end
    end
  end

  describe "refute_tenant/1" do
    test "passes when tenant is different" do
      TestHelpers.set_current("different-tenant")
      TestHelpers.refute_tenant("unwanted-tenant")
    end

    test "fails when tenant matches" do
      TestHelpers.set_current("matching-tenant")
      
      assert_raise ExUnit.AssertionError, ~r/Expected tenant not to be "matching-tenant"/, fn ->
        TestHelpers.refute_tenant("matching-tenant")
      end
    end
  end

  describe "assert_tenant_present/0" do
    test "passes when tenant is set" do
      TestHelpers.set_current("present-tenant")
      TestHelpers.assert_tenant_present()
    end

    test "fails when no tenant is set" do
      TestHelpers.clear_tenant()
      
      assert_raise ExUnit.AssertionError, ~r/Expected tenant to be present/, fn ->
        TestHelpers.assert_tenant_present()
      end
    end
  end

  describe "assert_no_tenant/0" do
    test "passes when no tenant is set" do
      TestHelpers.clear_tenant()
      TestHelpers.assert_no_tenant()
    end

    test "fails when tenant is set" do
      TestHelpers.set_current("unexpected-tenant")
      
      assert_raise ExUnit.AssertionError, ~r/Expected no tenant to be set/, fn ->
        TestHelpers.assert_no_tenant()
      end
    end
  end

  describe "create_test_snapshot/1" do
    test "creates snapshot with tenant data" do
      snapshot = TestHelpers.create_test_snapshot("snapshot-tenant")
      
      assert is_map(snapshot)
      assert snapshot[:tenant_plug_tenant] == "snapshot-tenant"
    end

    test "snapshot can be applied" do
      snapshot = TestHelpers.create_test_snapshot("applied-tenant")
      TenantPlug.apply_snapshot(snapshot)
      
      assert TenantPlug.current() == "applied-tenant"
    end
  end

  describe "capture_telemetry_events/1" do
    test "captures telemetry events from function" do
      events = TestHelpers.capture_telemetry_events(fn ->
        TenantPlug.Telemetry.tenant_resolved("telemetry-tenant", %{})
      end)
      
      resolved_events = Enum.filter(events, fn event ->
        event.event == [:tenant_plug, :tenant, :resolved] and
        event.metadata.tenant == "telemetry-tenant"
      end)
      
      assert length(resolved_events) >= 1
      event = List.first(resolved_events)
      assert event.event == [:tenant_plug, :tenant, :resolved]
      assert event.metadata.tenant == "telemetry-tenant"
    end

    test "captures multiple events" do
      events = TestHelpers.capture_telemetry_events(fn ->
        TenantPlug.Telemetry.tenant_resolved("tenant1", %{})
        TenantPlug.Telemetry.tenant_cleared(%{})
        TenantPlug.Telemetry.tenant_resolved("tenant2", %{})
      end)
      
      # Filter for the specific events we expect
      relevant_events = Enum.filter(events, fn event ->
        case event.event do
          [:tenant_plug, :tenant, :resolved] -> 
            event.metadata.tenant in ["tenant1", "tenant2"]
          [:tenant_plug, :tenant, :cleared] -> 
            true
          _ -> 
            false
        end
      end)
      
      assert length(relevant_events) >= 3
    end

    test "returns empty list when no events" do
      # Test that a function that makes no telemetry calls produces no events
      # Use a unique function that we know doesn't generate telemetry
      events = TestHelpers.capture_telemetry_events(fn ->
        # Simple operation that should not generate any tenant_plug telemetry
        1 + 1
      end)
      
      # Filter for any events that were generated during our specific function call
      # We should not see any events with metadata that indicates they came from our function
      function_generated_events = Enum.filter(events, fn event ->
        # Look for events that don't have metadata from previous tests
        case event.metadata do
          %{tenant: tenant} when tenant in ["attach-test", "detach-test"] -> false
          %{error: error} when is_binary(error) -> false  # From previous error tests
          _ -> 
            case event.event do
              [:tenant_plug | _] -> true
              _ -> false
            end
        end
      end)
      
      assert function_generated_events == []
    end
  end

  describe "__using__ macro" do
    test "automatically clears tenant context in setup" do
      # This test verifies that the __using__ macro works correctly
      # The setup should have already cleared any existing tenant
      assert TenantPlug.current() == nil
    end
  end

  describe "mock_source/2 and clear_mocks/0" do
    test "mock_source stores mock configuration" do
      TestHelpers.mock_source(TenantPlug.Sources.FromHeader, {:ok, "mocked-tenant"})
      
      # Verify mock is stored (implementation detail, but useful for testing)
      assert Process.get({:tenant_plug_mock, TenantPlug.Sources.FromHeader}) == {:ok, "mocked-tenant"}
    end

    test "clear_mocks removes all mock configurations" do
      TestHelpers.mock_source(TenantPlug.Sources.FromHeader, {:ok, "mock1"})
      TestHelpers.mock_source(TenantPlug.Sources.FromSubdomain, {:ok, "mock2"})
      
      TestHelpers.clear_mocks()
      
      assert Process.get({:tenant_plug_mock, TenantPlug.Sources.FromHeader}) == nil
      assert Process.get({:tenant_plug_mock, TenantPlug.Sources.FromSubdomain}) == nil
    end
  end

  # Helper function to check if JWT token contains specific claim
  defp token_contains_claim?(token, claim_key, expected_value) do
    case String.split(token, ".") do
      [_header, payload_part | _] ->
        case Base.url_decode64(add_padding(payload_part)) do
          {:ok, json} ->
            case Jason.decode(json) do
              {:ok, payload} ->
                Map.get(payload, claim_key) == expected_value
              _ ->
                false
            end
          _ ->
            false
        end
      _ ->
        false
    end
  end

  defp add_padding(string) do
    case rem(String.length(string), 4) do
      0 -> string
      2 -> string <> "=="
      3 -> string <> "="
      _ -> string
    end
  end
end