defmodule TenantPlug.Context do
  @moduledoc """
  Process-local tenant context storage using the process dictionary.

  This module provides functions to store and retrieve tenant information
  within the current process, making it available throughout the request
  lifecycle without explicitly passing it around.
  """

  @default_key :tenant_plug_tenant

  @doc """
  Set the tenant in the current process context.

  ## Examples

      iex> TenantPlug.Context.set("tenant-123")
      :ok

      iex> TenantPlug.Context.set("tenant-456", :custom_key)
      :ok
  """
  @spec set(term(), atom()) :: :ok
  def set(tenant, key \\ @default_key) do
    Process.put(key, tenant)
    :ok
  end

  @doc """
  Get the tenant from the current process context.

  Returns `nil` if no tenant is set.

  ## Examples

      iex> TenantPlug.Context.set("tenant-123")
      iex> TenantPlug.Context.get()
      "tenant-123"

      iex> TenantPlug.Context.get(:nonexistent_key)
      nil
  """
  @spec get(atom()) :: term() | nil
  def get(key \\ @default_key) do
    Process.get(key)
  end

  @doc """
  Clear the tenant from the current process context.

  ## Examples

      iex> TenantPlug.Context.set("tenant-123")
      iex> TenantPlug.Context.clear()
      :ok
      iex> TenantPlug.Context.get()
      nil
  """
  @spec clear(atom()) :: :ok
  def clear(key \\ @default_key) do
    Process.delete(key)
    :ok
  end

  @doc """
  Create a snapshot of the current tenant context.

  This captures all tenant-related keys from the process dictionary,
  which can be restored later using `apply_snapshot/1`.

  Useful for preserving tenant context across process boundaries.

  ## Examples

      iex> TenantPlug.Context.set("tenant-123")
      iex> snapshot = TenantPlug.Context.snapshot()
      iex> is_map(snapshot)
      true
  """
  @spec snapshot() :: map() | nil
  def snapshot do
    process_dict = Process.get()
    
    tenant_keys = 
      process_dict
      |> Enum.filter(fn {key, _value} -> 
        is_atom(key) and String.starts_with?(Atom.to_string(key), "tenant_plug")
      end)
      |> Enum.into(%{})

    case tenant_keys do
      empty when map_size(empty) == 0 -> nil
      keys -> keys
    end
  end

  @doc """
  Apply a tenant context snapshot to the current process.

  This restores tenant context from a snapshot created by `snapshot/0`.

  ## Examples

      # In the original process
      TenantPlug.Context.set("tenant-123")
      snapshot = TenantPlug.Context.snapshot()

      # In a new process (e.g., background job)
      TenantPlug.Context.apply_snapshot(snapshot)
      TenantPlug.Context.get() # Returns "tenant-123"
  """
  @spec apply_snapshot(map() | nil) :: :ok
  def apply_snapshot(nil), do: :ok
  
  def apply_snapshot(snapshot) when is_map(snapshot) do
    Enum.each(snapshot, fn {key, value} ->
      Process.put(key, value)
    end)
    
    :ok
  end

  @doc """
  Check if a tenant is currently set in the process context.

  ## Examples

      iex> TenantPlug.Context.present?()
      false

      iex> TenantPlug.Context.set("tenant-123")
      iex> TenantPlug.Context.present?()
      true
  """
  @spec present?(atom()) :: boolean()
  def present?(key \\ @default_key) do
    get(key) != nil
  end

  @doc """
  Get the tenant, raising an error if not present.

  ## Examples

      iex> TenantPlug.Context.set("tenant-123")
      iex> TenantPlug.Context.get!()
      "tenant-123"

      iex> TenantPlug.Context.clear()
      iex> TenantPlug.Context.get!()
      ** (RuntimeError) No tenant found in process context
  """
  @spec get!(atom()) :: term()
  def get!(key \\ @default_key) do
    case get(key) do
      nil -> raise "No tenant found in process context"
      tenant -> tenant
    end
  end

  @doc """
  Execute a function with a specific tenant context.

  The tenant context is automatically restored after the function executes.

  ## Examples

      iex> TenantPlug.Context.with_tenant("temp-tenant", fn ->
      ...>   TenantPlug.Context.get()
      ...> end)
      "temp-tenant"
  """
  @spec with_tenant(term(), fun(), atom()) :: term()
  def with_tenant(tenant, fun, key \\ @default_key) when is_function(fun, 0) do
    original = get(key)
    
    try do
      set(tenant, key)
      fun.()
    after
      case original do
        nil -> clear(key)
        value -> set(value, key)
      end
    end
  end
end