defmodule TenantPlug do
  @moduledoc """
  A Plug for automatic tenant context management in Phoenix and Plug-based applications.

  TenantPlug extracts tenant information from HTTP requests using configurable sources
  and stores it in process-local context for easy access throughout the request lifecycle.

  ## Configuration

  * `:sources` - List of extraction modules to run (in order). Default: `[TenantPlug.Sources.FromHeader]`
  * `:key` - Process dictionary key for storing tenant. Default: `:tenant_plug_tenant`
  * `:logger_metadata` - Enable automatic logger metadata injection. Default: `true`
  * `:telemetry` - Enable telemetry events. Default: `true`
  * `:require_resolved` - Halt request if no tenant is resolved. Default: `false`

  ## Usage

      # In your Phoenix endpoint or router
      plug TenantPlug, sources: [
        TenantPlug.Sources.FromHeader,
        TenantPlug.Sources.FromSubdomain
      ]

      # Later in your application
      tenant_id = TenantPlug.current()

  ## Telemetry Events

  * `[:tenant_plug, :tenant, :resolved]` - Tenant successfully resolved
  * `[:tenant_plug, :tenant, :cleared]` - Tenant context cleared
  * `[:tenant_plug, :error, :source_exception]` - Source raised an exception
  * `[:tenant_plug, :error, :source_error]` - Source returned an error
  """

  @behaviour Plug

  alias TenantPlug.{Context, Logger, Telemetry}

  @default_opts [
    sources: [TenantPlug.Sources.FromHeader],
    key: :tenant_plug_tenant,
    logger_metadata: true,
    telemetry: true,
    require_resolved: false
  ]

  @doc """
  Initialize the plug with options.
  """
  @impl Plug
  def init(opts) do
    @default_opts
    |> Keyword.merge(opts)
    |> validate_opts!()
  end

  @doc """
  Execute the plug to extract and set tenant context.
  """
  @impl Plug
  def call(conn, opts) do
    with {:ok, tenant} <- extract_tenant(conn, opts) do
      Context.set(tenant, opts[:key])
      
      if opts[:logger_metadata] do
        Logger.set_metadata(tenant)
      end

      if opts[:telemetry] do
        Telemetry.tenant_resolved(tenant, %{conn: conn, opts: opts})
      end

      conn
    else
      {:error, reason} ->
        if opts[:telemetry] do
          Telemetry.source_error(reason, %{conn: conn, opts: opts})
        end

        if opts[:require_resolved] do
          conn
          |> Plug.Conn.put_status(:bad_request)
          |> Plug.Conn.halt()
        else
          conn
        end

      :not_found ->
        if opts[:require_resolved] do
          conn
          |> Plug.Conn.put_status(:bad_request)
          |> Plug.Conn.halt()
        else
          conn
        end
    end
  end

  @doc """
  Get the current tenant from process context.

  Returns `nil` if no tenant is set.

  ## Examples

      iex> TenantPlug.Context.set("tenant-123")
      iex> TenantPlug.current()
      "tenant-123"

      iex> TenantPlug.Context.clear()
      iex> TenantPlug.current()
      nil
  """
  @spec current() :: term() | nil
  def current do
    Context.get()
  end

  @doc """
  Create a snapshot of the current tenant context.

  Useful for preserving tenant context across process boundaries,
  such as when spawning background jobs.

  ## Examples

      snapshot = TenantPlug.snapshot()
      Task.async(fn ->
        TenantPlug.apply_snapshot(snapshot)
        # Now the background task has access to the tenant context
        do_background_work()
      end)
  """
  @spec snapshot() :: map() | nil
  def snapshot do
    Context.snapshot()
  end

  @doc """
  Apply a tenant context snapshot to the current process.

  ## Examples

      TenantPlug.apply_snapshot(snapshot)
      TenantPlug.current() # Returns the tenant from the snapshot
  """
  @spec apply_snapshot(map() | nil) :: :ok
  def apply_snapshot(snapshot) do
    Context.apply_snapshot(snapshot)
  end

  @doc """
  Clear the current tenant context.

  Useful for testing or manual context management.
  """
  @spec clear() :: :ok
  def clear do
    Context.clear()
    Telemetry.tenant_cleared(%{})
    :ok
  end

  # Private functions

  defp extract_tenant(conn, opts) do
    sources = opts[:sources] || []
    
    Enum.reduce_while(sources, :not_found, fn source, _acc ->
      try do
        case source.extract(conn, opts) do
          {:ok, tenant} when tenant != nil ->
            {:halt, {:ok, tenant}}
          
          {:ok, nil} ->
            {:cont, :not_found}
          
          :not_found ->
            {:cont, :not_found}
          
          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      rescue
        error ->
          if opts[:telemetry] do
            Telemetry.source_exception(error, %{
              source: source,
              conn: conn,
              opts: opts
            })
          end
          
          {:cont, :not_found}
      end
    end)
  end

  defp validate_opts!(opts) do
    with :ok <- validate_sources(opts[:sources]),
         :ok <- validate_key(opts[:key]),
         :ok <- validate_boolean_opt(opts[:logger_metadata], :logger_metadata),
         :ok <- validate_boolean_opt(opts[:telemetry], :telemetry),
         :ok <- validate_boolean_opt(opts[:require_resolved], :require_resolved) do
      opts
    else
      {:error, message} ->
        raise ArgumentError, message
    end
  end

  defp validate_sources(sources) when is_list(sources) do
    invalid_sources = 
      Enum.reject(sources, fn source ->
        Code.ensure_loaded?(source) and 
        function_exported?(source, :extract, 2)
      end)

    case invalid_sources do
      [] -> :ok
      _ -> {:error, "Invalid sources: #{inspect(invalid_sources)}. Sources must implement extract/2."}
    end
  end

  defp validate_sources(_), do: {:error, ":sources must be a list"}

  defp validate_key(key) when is_atom(key), do: :ok
  defp validate_key(_), do: {:error, ":key must be an atom"}

  defp validate_boolean_opt(value, _name) when is_boolean(value), do: :ok
  defp validate_boolean_opt(_, name), do: {:error, ":#{name} must be a boolean"}
end