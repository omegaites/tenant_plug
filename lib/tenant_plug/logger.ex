defmodule TenantPlug.Logger do
  @moduledoc """
  Logger metadata integration for tenant context.

  This module provides automatic logger metadata injection for tenant information,
  making it easy to filter and search logs by tenant. When enabled, the tenant ID
  is automatically added to all log entries within the request context.

  ## Configuration

  Logger metadata can be enabled/disabled via the `:logger_metadata` option
  in TenantPlug configuration.

  ## Usage

      # Logger metadata is enabled by default
      plug TenantPlug

      # Explicitly enable logger metadata
      plug TenantPlug, logger_metadata: true

      # Disable logger metadata
      plug TenantPlug, logger_metadata: false

  ## Example Log Output

      # Without tenant metadata
      [info] Processing request

      # With tenant metadata
      [info] tenant_id=acme Processing request

  ## Custom Metadata Keys

  You can customize the metadata key used for tenant information:

      # Use custom metadata key
      plug TenantPlug, logger_metadata: true, metadata_key: :org_id

  ## Structured Logging

  The tenant information is also available for structured logging:

      Logger.metadata()[:tenant_id]  # Returns current tenant ID

  ## Background Jobs

  When using snapshots for background jobs, logger metadata is preserved:

      snapshot = TenantPlug.snapshot()
      
      Task.async(fn ->
        TenantPlug.apply_snapshot(snapshot)
        # Logger metadata is automatically restored
        Logger.info("Background job started")  # Includes tenant metadata
      end)
  """

  require Logger

  @default_metadata_key :tenant_id

  @doc """
  Set tenant metadata for the current process.

  This function adds the tenant ID to the logger metadata for the current process,
  making it available in all subsequent log entries.

  ## Examples

      iex> TenantPlug.Logger.set_metadata("tenant-123")
      :ok

      iex> TenantPlug.Logger.set_metadata("acme", :org_id)  
      :ok

      iex> Logger.metadata()[:tenant_id]
      "tenant-123"
  """
  @spec set_metadata(term(), atom()) :: :ok
  def set_metadata(tenant, key \\ @default_metadata_key) do
    current_metadata = Logger.metadata()
    new_metadata = Keyword.put(current_metadata, key, tenant)
    Logger.metadata(new_metadata)
    :ok
  end

  @doc """
  Clear tenant metadata for the current process.

  ## Examples

      iex> TenantPlug.Logger.clear_metadata()
      :ok

      iex> TenantPlug.Logger.clear_metadata(:org_id)
      :ok
  """
  @spec clear_metadata(atom()) :: :ok
  def clear_metadata(key \\ @default_metadata_key) do
    current_metadata = Logger.metadata()
    
    case Keyword.has_key?(current_metadata, key) do
      true ->
        new_metadata = Keyword.delete(current_metadata, key)
        Logger.reset_metadata()
        Logger.metadata(new_metadata)
        
      false ->
        :ok
    end
    
    :ok
  end

  @doc """
  Get the current tenant from logger metadata.

  ## Examples

      iex> TenantPlug.Logger.set_metadata("tenant-123")
      iex> TenantPlug.Logger.get_metadata()
      "tenant-123"

      iex> TenantPlug.Logger.get_metadata(:nonexistent)
      nil
  """
  @spec get_metadata(atom()) :: term() | nil
  def get_metadata(key \\ @default_metadata_key) do
    Logger.metadata()[key]
  end

  @doc """
  Execute a function with specific tenant metadata.

  The tenant metadata is automatically restored after the function executes.

  ## Examples

      iex> TenantPlug.Logger.with_metadata("temp-tenant", fn ->
      ...>   Logger.info("This log will include temp-tenant")
      ...>   TenantPlug.Logger.get_metadata()
      ...> end)
      "temp-tenant"
  """
  @spec with_metadata(term(), fun(), atom()) :: term()
  def with_metadata(tenant, fun, key \\ @default_metadata_key) when is_function(fun, 0) do
    original = get_metadata(key)
    
    try do
      set_metadata(tenant, key)
      fun.()
    after
      case original do
        nil -> clear_metadata(key)
        value -> set_metadata(value, key)
      end
    end
  end

  @doc """
  Check if tenant metadata is present.

  ## Examples

      iex> TenantPlug.Logger.present?()
      false

      iex> TenantPlug.Logger.set_metadata("tenant-123")
      iex> TenantPlug.Logger.present?()
      true
  """
  @spec present?(atom()) :: boolean()
  def present?(key \\ @default_metadata_key) do
    get_metadata(key) != nil
  end

  @doc """
  Get all tenant-related metadata.

  Returns all logger metadata keys that start with 'tenant' or 'org'.

  ## Examples

      iex> TenantPlug.Logger.set_metadata("tenant-123")
      iex> TenantPlug.Logger.get_all_tenant_metadata()
      [tenant_id: "tenant-123"]
  """
  @spec get_all_tenant_metadata() :: keyword()
  def get_all_tenant_metadata do
    Logger.metadata()
    |> Enum.filter(fn {key, _value} ->
      key_string = Atom.to_string(key)
      String.contains?(key_string, "tenant") or String.contains?(key_string, "org")
    end)
  end

  @doc """
  Create a metadata snapshot that can be restored later.

  This is useful for preserving tenant metadata across process boundaries.

  ## Examples

      snapshot = TenantPlug.Logger.snapshot_metadata()
      
      Task.async(fn ->
        TenantPlug.Logger.restore_metadata(snapshot)
        # Tenant metadata is now available in the background task
      end)
  """
  @spec snapshot_metadata() :: keyword()
  def snapshot_metadata do
    get_all_tenant_metadata()
  end

  @doc """
  Restore metadata from a snapshot.

  ## Examples

      TenantPlug.Logger.restore_metadata([tenant_id: "tenant-123"])
  """
  @spec restore_metadata(keyword()) :: :ok
  def restore_metadata(metadata_snapshot) when is_list(metadata_snapshot) do
    current_metadata = Logger.metadata()
    
    new_metadata = 
      metadata_snapshot
      |> Enum.reduce(current_metadata, fn {key, value}, acc ->
        Keyword.put(acc, key, value)
      end)
    
    Logger.metadata(new_metadata)
    :ok
  end

  def restore_metadata(_), do: :ok

  @doc """
  Log a message with explicit tenant context.

  This is useful when you want to log with a specific tenant context
  without changing the process metadata.

  ## Examples

      TenantPlug.Logger.log_with_tenant(:info, "Processing request", "tenant-123")
  """
  @spec log_with_tenant(Logger.level(), String.t(), term(), atom()) :: :ok
  def log_with_tenant(level, message, tenant, key \\ @default_metadata_key) do
    with_metadata(tenant, fn ->
      Logger.log(level, message)
    end, key)
  end

  @doc """
  Get the default metadata key used for tenant information.

  ## Examples

      iex> TenantPlug.Logger.default_metadata_key()
      :tenant_id
  """
  @spec default_metadata_key() :: atom()
  def default_metadata_key, do: @default_metadata_key

  @doc """
  Format tenant information for inclusion in log messages.

  ## Examples

      iex> TenantPlug.Logger.format_tenant("tenant-123")
      "[tenant: tenant-123]"

      iex> TenantPlug.Logger.format_tenant(nil)
      ""
  """
  @spec format_tenant(term()) :: String.t()
  def format_tenant(nil), do: ""
  def format_tenant(tenant) when is_binary(tenant) or is_atom(tenant) or is_number(tenant) do
    "[tenant: #{tenant}]"
  end
  def format_tenant(tenant), do: "[tenant: #{inspect(tenant)}]"

  @doc """
  Configure logger backend to include tenant information in formatted output.

  This is a utility function that can be used in your application's logger
  configuration to automatically include tenant information in log formatting.

  ## Examples

      # In config/config.exs
      config :logger, :console,
        format: "$time $metadata[$level] $message\\n",
        metadata: [:tenant_id, :request_id]
  """
  @spec configure_logger_format(keyword()) :: keyword()
  def configure_logger_format(current_config \\ []) do
    metadata = Keyword.get(current_config, :metadata, [])
    
    tenant_keys = [@default_metadata_key, :org_id, :organization_id]
    updated_metadata = Enum.uniq(metadata ++ tenant_keys)
    
    Keyword.put(current_config, :metadata, updated_metadata)
  end
end