defmodule TenantPlug.LoggerTest do
  use ExUnit.Case, async: false  # Logger metadata is global

  alias TenantPlug.Logger, as: TenantLogger

  setup do
    # Clear logger metadata before each test
    Logger.metadata([])
    on_exit(fn -> Logger.metadata([]) end)
    :ok
  end

  describe "set_metadata/2" do
    test "sets tenant metadata with default key" do
      TenantLogger.set_metadata("logger-tenant")
      
      assert Logger.metadata()[:tenant_id] == "logger-tenant"
    end

    test "sets tenant metadata with custom key" do
      TenantLogger.set_metadata("custom-tenant", :org_id)
      
      assert Logger.metadata()[:org_id] == "custom-tenant"
    end

    test "preserves existing metadata" do
      Logger.metadata(existing_key: "existing_value")
      TenantLogger.set_metadata("new-tenant")
      
      metadata = Logger.metadata()
      assert metadata[:tenant_id] == "new-tenant"
      assert metadata[:existing_key] == "existing_value"
    end
  end

  describe "clear_metadata/1" do
    test "clears tenant metadata with default key" do
      TenantLogger.set_metadata("to-be-cleared")
      TenantLogger.clear_metadata()
      
      assert Logger.metadata()[:tenant_id] == nil
    end

    test "clears tenant metadata with custom key" do
      TenantLogger.set_metadata("custom-to-clear", :custom_key)
      TenantLogger.clear_metadata(:custom_key)
      
      assert Logger.metadata()[:custom_key] == nil
    end

    test "preserves other metadata when clearing" do
      Logger.metadata(keep_this: "keep_value")
      TenantLogger.set_metadata("clear-this")
      
      TenantLogger.clear_metadata()
      
      metadata = Logger.metadata()
      assert metadata[:tenant_id] == nil
      assert metadata[:keep_this] == "keep_value"
    end
  end

  describe "get_metadata/1" do
    test "gets tenant metadata with default key" do
      TenantLogger.set_metadata("get-tenant")
      
      assert TenantLogger.get_metadata() == "get-tenant"
    end

    test "gets tenant metadata with custom key" do
      TenantLogger.set_metadata("custom-get", :custom_get_key)
      
      assert TenantLogger.get_metadata(:custom_get_key) == "custom-get"
    end

    test "returns nil for non-existent key" do
      assert TenantLogger.get_metadata(:non_existent) == nil
    end
  end

  describe "with_metadata/3" do
    test "executes function with temporary metadata" do
      result = TenantLogger.with_metadata("temp-tenant", fn ->
        assert TenantLogger.get_metadata() == "temp-tenant"
        "function-result"
      end)
      
      assert result == "function-result"
      assert TenantLogger.get_metadata() == nil
    end

    test "restores original metadata after execution" do
      TenantLogger.set_metadata("original-tenant")
      
      TenantLogger.with_metadata("temp-tenant", fn ->
        assert TenantLogger.get_metadata() == "temp-tenant"
      end)
      
      assert TenantLogger.get_metadata() == "original-tenant"
    end

    test "restores metadata after exception" do
      TenantLogger.set_metadata("exception-original")
      
      assert_raise RuntimeError, fn ->
        TenantLogger.with_metadata("exception-temp", fn ->
          raise "Test exception"
        end)
      end
      
      assert TenantLogger.get_metadata() == "exception-original"
    end

    test "works with custom key" do
      TenantLogger.set_metadata("original-custom", :custom_meta)
      
      TenantLogger.with_metadata("temp-custom", fn ->
        assert TenantLogger.get_metadata(:custom_meta) == "temp-custom"
      end, :custom_meta)
      
      assert TenantLogger.get_metadata(:custom_meta) == "original-custom"
    end
  end

  describe "present?/1" do
    test "returns false when no metadata is set" do
      assert TenantLogger.present?() == false
    end

    test "returns true when metadata is set" do
      TenantLogger.set_metadata("present-tenant")
      assert TenantLogger.present?() == true
    end

    test "works with custom key" do
      TenantLogger.set_metadata("custom-present", :custom_present_key)
      assert TenantLogger.present?(:custom_present_key) == true
      assert TenantLogger.present?(:not_present_key) == false
    end
  end

  describe "get_all_tenant_metadata/0" do
    test "returns empty list when no tenant metadata" do
      Logger.metadata(other_key: "other_value")
      assert TenantLogger.get_all_tenant_metadata() == []
    end

    test "returns tenant-related metadata" do
      Logger.metadata([
        tenant_id: "tenant-123",
        org_id: "org-456", 
        other_key: "other_value"
      ])
      
      tenant_metadata = TenantLogger.get_all_tenant_metadata()
      
      assert Keyword.get(tenant_metadata, :tenant_id) == "tenant-123"
      assert Keyword.get(tenant_metadata, :org_id) == "org-456"
      assert Keyword.get(tenant_metadata, :other_key) == nil
    end
  end

  describe "snapshot_metadata/0 and restore_metadata/1" do
    test "creates and restores metadata snapshot" do
      TenantLogger.set_metadata("snapshot-tenant")
      Logger.metadata(org_id: "snapshot-org")
      
      snapshot = TenantLogger.snapshot_metadata()
      
      TenantLogger.clear_metadata()
      Logger.metadata(org_id: nil)
      
      TenantLogger.restore_metadata(snapshot)
      
      assert TenantLogger.get_metadata() == "snapshot-tenant"
      assert Logger.metadata()[:org_id] == "snapshot-org"
    end

    test "handles empty snapshot" do
      TenantLogger.restore_metadata([])
      assert TenantLogger.get_metadata() == nil
    end

    test "handles nil snapshot" do
      TenantLogger.restore_metadata(nil)
      assert TenantLogger.get_metadata() == nil
    end
  end

  describe "log_with_tenant/4" do
    test "logs with temporary tenant context" do
      # Capture log output
      log_output = capture_log(fn ->
        TenantLogger.log_with_tenant(:info, "Test message", "log-tenant")
      end)
      
      # The exact format depends on logger configuration, but tenant should be included
      assert log_output != ""
    end

    test "doesn't affect global metadata" do
      TenantLogger.set_metadata("global-tenant")
      
      capture_log(fn ->
        TenantLogger.log_with_tenant(:info, "Test message", "temp-tenant")
      end)
      
      assert TenantLogger.get_metadata() == "global-tenant"
    end
  end

  describe "format_tenant/1" do
    test "formats tenant information" do
      assert TenantLogger.format_tenant("test-tenant") == "[tenant: test-tenant]"
    end

    test "handles nil tenant" do
      assert TenantLogger.format_tenant(nil) == ""
    end

    test "handles complex tenant data" do
      tenant_map = %{id: "123", name: "Acme"}
      result = TenantLogger.format_tenant(tenant_map)
      assert String.contains?(result, "tenant:")
    end
  end

  describe "configure_logger_format/1" do
    test "adds tenant metadata to logger configuration" do
      current_config = [format: "$message", metadata: [:request_id]]
      
      updated_config = TenantLogger.configure_logger_format(current_config)
      
      metadata = Keyword.get(updated_config, :metadata)
      assert :tenant_id in metadata
      assert :org_id in metadata
      assert :request_id in metadata
    end

    test "handles empty configuration" do
      config = TenantLogger.configure_logger_format([])
      
      metadata = Keyword.get(config, :metadata)
      assert :tenant_id in metadata
    end

    test "doesn't duplicate existing tenant keys" do
      current_config = [metadata: [:tenant_id, :other_key]]
      
      updated_config = TenantLogger.configure_logger_format(current_config)
      metadata = Keyword.get(updated_config, :metadata)
      
      # Should not have duplicate tenant_id
      assert length(Enum.filter(metadata, &(&1 == :tenant_id))) == 1
    end
  end

  describe "default_metadata_key/0" do
    test "returns default metadata key" do
      assert TenantLogger.default_metadata_key() == :tenant_id
    end
  end

  # Helper function to capture log output
  defp capture_log(fun) do
    ExUnit.CaptureLog.capture_log(fun)
  end
end