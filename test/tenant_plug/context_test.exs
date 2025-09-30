defmodule TenantPlug.ContextTest do
  use ExUnit.Case, async: true
  
  alias TenantPlug.Context

  doctest TenantPlug.Context

  describe "set/2 and get/1" do
    test "sets and gets tenant with default key" do
      Context.set("test-tenant")
      assert Context.get() == "test-tenant"
    end

    test "sets and gets tenant with custom key" do
      Context.set("custom-tenant", :custom_key)
      assert Context.get(:custom_key) == "custom-tenant"
    end

    test "returns nil for non-existent key" do
      assert Context.get(:non_existent) == nil
    end

    test "handles different data types" do
      tenant_map = %{id: "tenant-123", name: "Acme Corp"}
      Context.set(tenant_map)
      assert Context.get() == tenant_map
    end
  end

  describe "clear/1" do
    test "clears tenant with default key" do
      Context.set("to-be-cleared")
      Context.clear()
      assert Context.get() == nil
    end

    test "clears tenant with custom key" do
      Context.set("custom-to-clear", :custom_clear)
      Context.clear(:custom_clear)
      assert Context.get(:custom_clear) == nil
    end

    test "only clears specified key" do
      Context.set("keep-this", :keep)
      Context.set("clear-this", :clear)
      
      Context.clear(:clear)
      
      assert Context.get(:keep) == "keep-this"
      assert Context.get(:clear) == nil
    end
  end

  describe "snapshot/0 and apply_snapshot/1" do
    test "creates snapshot of tenant context" do
      Context.set("snapshot-tenant")
      snapshot = Context.snapshot()
      
      assert is_map(snapshot)
      assert snapshot[:tenant_plug_tenant] == "snapshot-tenant"
    end

    test "returns nil when no tenant context exists" do
      Context.clear()
      assert Context.snapshot() == nil
    end

    test "applies snapshot to restore context" do
      snapshot = %{tenant_plug_tenant: "restored-tenant"}
      Context.apply_snapshot(snapshot)
      
      assert Context.get() == "restored-tenant"
    end

    test "handles nil snapshot gracefully" do
      Context.apply_snapshot(nil)
      assert Context.get() == nil
    end

    test "captures multiple tenant-related keys" do
      Context.set("main-tenant", :tenant_plug_tenant)
      Context.set("org-123", :tenant_plug_org)
      
      snapshot = Context.snapshot()
      
      assert snapshot[:tenant_plug_tenant] == "main-tenant"
      assert snapshot[:tenant_plug_org] == "org-123"
    end

    test "ignores non-tenant keys in snapshot" do
      Context.set("tenant-value", :tenant_plug_tenant)
      Process.put(:other_key, "other-value")
      
      snapshot = Context.snapshot()
      
      assert snapshot[:tenant_plug_tenant] == "tenant-value"
      assert Map.has_key?(snapshot, :other_key) == false
    end
  end

  describe "present?/1" do
    test "returns false when no tenant is set" do
      Context.clear()
      assert Context.present?() == false
    end

    test "returns true when tenant is set" do
      Context.set("present-tenant")
      assert Context.present?() == true
    end

    test "works with custom keys" do
      Context.set("custom-present", :custom_present)
      assert Context.present?(:custom_present) == true
      assert Context.present?(:not_present) == false
    end
  end

  describe "get!/1" do
    test "returns tenant when present" do
      Context.set("required-tenant")
      assert Context.get!() == "required-tenant"
    end

    test "raises error when tenant not present" do
      Context.clear()
      
      assert_raise RuntimeError, "No tenant found in process context", fn ->
        Context.get!()
      end
    end

    test "works with custom keys" do
      Context.set("custom-required", :custom_required)
      assert Context.get!(:custom_required) == "custom-required"
      
      assert_raise RuntimeError, fn ->
        Context.get!(:missing_required)
      end
    end
  end

  describe "with_tenant/3" do
    test "executes function with temporary tenant context" do
      Context.set("original-tenant")
      
      result = Context.with_tenant("temp-tenant", fn ->
        assert Context.get() == "temp-tenant"
        "function-result"
      end)
      
      assert result == "function-result"
      assert Context.get() == "original-tenant"
    end

    test "restores context after exception" do
      Context.set("original-before-exception")
      
      assert_raise RuntimeError, fn ->
        Context.with_tenant("temp-tenant", fn ->
          raise "Test exception"
        end)
      end
      
      assert Context.get() == "original-before-exception"
    end

    test "works when no original tenant was set" do
      Context.clear()
      
      Context.with_tenant("temp-only", fn ->
        assert Context.get() == "temp-only"
      end)
      
      assert Context.get() == nil
    end

    test "works with custom keys" do
      Context.set("original-custom", :custom_with)
      
      Context.with_tenant("temp-custom", fn ->
        assert Context.get(:custom_with) == "temp-custom"
      end, :custom_with)
      
      assert Context.get(:custom_with) == "original-custom"
    end
  end

  describe "process isolation" do
    test "tenant context is isolated between processes" do
      Context.set("main-process-tenant")
      
      task = Task.async(fn ->
        # Should not see tenant from main process
        assert Context.get() == nil
        
        # Set tenant in task process
        Context.set("task-process-tenant")
        Context.get()
      end)
      
      task_tenant = Task.await(task)
      
      # Task should have its own tenant
      assert task_tenant == "task-process-tenant"
      
      # Main process should still have its tenant
      assert Context.get() == "main-process-tenant"
    end

    test "snapshots enable context sharing between processes" do
      Context.set("shared-tenant")
      snapshot = Context.snapshot()
      
      task = Task.async(fn ->
        Context.apply_snapshot(snapshot)
        Context.get()
      end)
      
      task_tenant = Task.await(task)
      assert task_tenant == "shared-tenant"
    end
  end
end