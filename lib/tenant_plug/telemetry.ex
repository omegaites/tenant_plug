defmodule TenantPlug.Telemetry do
  @moduledoc """
  Telemetry instrumentation for TenantPlug operations.

  This module provides telemetry events for monitoring and observability of tenant
  resolution operations. Events are emitted for successful tenant resolution,
  errors, and context management operations.

  ## Telemetry Events

  All events are prefixed with `[:tenant_plug]` and include relevant metadata.

  ### Success Events

  * `[:tenant_plug, :tenant, :resolved]` - Tenant successfully resolved
    - Measurements: `%{count: 1, duration: microseconds}`
    - Metadata: `%{tenant: term(), source: module(), conn: Plug.Conn.t(), opts: keyword()}`

  * `[:tenant_plug, :tenant, :cleared]` - Tenant context cleared
    - Measurements: `%{count: 1}`
    - Metadata: `%{tenant: term() | nil}`

  ### Error Events

  * `[:tenant_plug, :error, :source_exception]` - Source raised an exception
    - Measurements: `%{count: 1}`
    - Metadata: `%{error: term(), source: module(), conn: Plug.Conn.t(), opts: keyword()}`

  * `[:tenant_plug, :error, :source_error]` - Source returned an error
    - Measurements: `%{count: 1}`
    - Metadata: `%{error: term(), conn: Plug.Conn.t(), opts: keyword()}`

  ## Usage with Telemetry Metrics

      import Telemetry.Metrics

      def metrics do
        [
          # Count tenant resolutions
          counter("tenant_plug.tenant.resolved.count"),
          
          # Monitor resolution duration
          distribution("tenant_plug.tenant.resolved.duration", unit: {:native, :microsecond}),
          
          # Count errors by source
          counter("tenant_plug.error.source_exception.count", tags: [:source]),
          
          # Count errors by type
          counter("tenant_plug.error.source_error.count")
        ]
      end

  ## Usage with Custom Handlers

      # Attach custom telemetry handler
      :telemetry.attach(
        "tenant-monitoring",
        [:tenant_plug, :tenant, :resolved],
        &MyApp.TenantMonitor.handle_event/4,
        %{}
      )

  ## Disabling Telemetry

  Telemetry can be disabled by setting `telemetry: false` in TenantPlug options:

      plug TenantPlug, telemetry: false
  """

  @doc """
  Emit telemetry event for successful tenant resolution.

  ## Examples

      TenantPlug.Telemetry.tenant_resolved("tenant-123", %{
        source: TenantPlug.Sources.FromHeader,
        conn: conn,
        opts: opts
      })
  """
  @spec tenant_resolved(term(), map()) :: :ok
  def tenant_resolved(tenant, metadata \\ %{}) do
    :telemetry.execute(
      [:tenant_plug, :tenant, :resolved],
      %{count: 1},
      Map.put(metadata, :tenant, tenant)
    )
    
    :ok
  end

  @doc """
  Emit telemetry event for tenant context cleared.

  ## Examples

      TenantPlug.Telemetry.tenant_cleared(%{tenant: "tenant-123"})
  """
  @spec tenant_cleared(map()) :: :ok
  def tenant_cleared(metadata \\ %{}) do
    :telemetry.execute(
      [:tenant_plug, :tenant, :cleared],
      %{count: 1},
      metadata
    )
    
    :ok
  end

  @doc """
  Emit telemetry event for source exceptions.

  ## Examples

      TenantPlug.Telemetry.source_exception(
        %RuntimeError{message: "Something went wrong"}, 
        %{source: MySource, conn: conn}
      )
  """
  @spec source_exception(term(), map()) :: :ok
  def source_exception(error, metadata \\ %{}) do
    :telemetry.execute(
      [:tenant_plug, :error, :source_exception],
      %{count: 1},
      Map.put(metadata, :error, error)
    )
    
    :ok
  end

  @doc """
  Emit telemetry event for source errors.

  ## Examples

      TenantPlug.Telemetry.source_error("Invalid token format", %{conn: conn})
  """
  @spec source_error(term(), map()) :: :ok
  def source_error(error, metadata \\ %{}) do
    :telemetry.execute(
      [:tenant_plug, :error, :source_error],
      %{count: 1},
      Map.put(metadata, :error, error)
    )
    
    :ok
  end

  @doc """
  Emit telemetry event for context snapshot creation.

  ## Examples

      TenantPlug.Telemetry.snapshot_created(%{tenant: "tenant-123"})
  """
  @spec snapshot_created(map()) :: :ok
  def snapshot_created(metadata \\ %{}) do
    :telemetry.execute(
      [:tenant_plug, :context, :snapshot_created],
      %{count: 1},
      metadata
    )
    
    :ok
  end

  @doc """
  Emit telemetry event for context snapshot application.

  ## Examples

      TenantPlug.Telemetry.snapshot_applied(%{tenant: "tenant-123"})
  """
  @spec snapshot_applied(map()) :: :ok
  def snapshot_applied(metadata \\ %{}) do
    :telemetry.execute(
      [:tenant_plug, :context, :snapshot_applied],
      %{count: 1},
      metadata
    )
    
    :ok
  end

  @doc """
  Execute a function and measure its duration, emitting telemetry events.

  ## Examples

      TenantPlug.Telemetry.measure(
        [:tenant_plug, :custom, :operation],
        %{custom_metadata: "value"},
        fn -> 
          # Your operation here
          :result
        end
      )
  """
  @spec measure([atom()], map(), fun()) :: term()
  def measure(event_name, metadata, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()
    
    try do
      result = fun.()
      duration = System.monotonic_time() - start_time
      
      :telemetry.execute(
        event_name,
        %{count: 1, duration: duration},
        Map.put(metadata, :result, :ok)
      )
      
      result
    rescue
      error ->
        duration = System.monotonic_time() - start_time
        
        :telemetry.execute(
          event_name,
          %{count: 1, duration: duration},
          Map.merge(metadata, %{result: :error, error: error})
        )
        
        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Span a function call with telemetry events for start and stop.

  ## Examples

      TenantPlug.Telemetry.span(
        [:tenant_plug, :source, :extract],
        %{source: MySource},
        fn -> 
          # Extraction logic
        end
      )
  """
  @spec span([atom()], map(), fun()) :: term()
  def span(event_prefix, metadata, fun) when is_function(fun, 0) do
    span_id = make_ref()
    start_metadata = Map.put(metadata, :span_id, span_id)
    
    :telemetry.execute(
      event_prefix ++ [:start],
      %{count: 1, monotonic_time: System.monotonic_time()},
      start_metadata
    )
    
    start_time = System.monotonic_time()
    
    try do
      result = fun.()
      duration = System.monotonic_time() - start_time
      
      stop_metadata = Map.merge(start_metadata, %{result: :ok})
      
      :telemetry.execute(
        event_prefix ++ [:stop],
        %{count: 1, duration: duration},
        stop_metadata
      )
      
      result
    rescue
      error ->
        duration = System.monotonic_time() - start_time
        
        stop_metadata = Map.merge(start_metadata, %{result: :error, error: error})
        
        :telemetry.execute(
          event_prefix ++ [:stop],
          %{count: 1, duration: duration},
          stop_metadata
        )
        
        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Get a list of all telemetry events emitted by TenantPlug.

  ## Examples

      iex> TenantPlug.Telemetry.events()
      [
        [:tenant_plug, :tenant, :resolved],
        [:tenant_plug, :tenant, :cleared],
        [:tenant_plug, :error, :source_exception],
        [:tenant_plug, :error, :source_error],
        [:tenant_plug, :context, :snapshot_created],
        [:tenant_plug, :context, :snapshot_applied]
      ]
  """
  @spec events() :: [[atom()]]
  def events do
    [
      [:tenant_plug, :tenant, :resolved],
      [:tenant_plug, :tenant, :cleared],
      [:tenant_plug, :error, :source_exception],
      [:tenant_plug, :error, :source_error],
      [:tenant_plug, :context, :snapshot_created],
      [:tenant_plug, :context, :snapshot_applied]
    ]
  end

  @doc """
  Attach a telemetry handler for all TenantPlug events.

  ## Examples

      TenantPlug.Telemetry.attach_all("my-handler", &my_handler_function/4, %{})
  """
  @spec attach_all(String.t(), fun(), map()) :: :ok | {:error, term()}
  def attach_all(handler_id, handler_function, config \\ %{}) do
    :telemetry.attach_many(
      handler_id,
      events(),
      handler_function,
      config
    )
  end

  @doc """
  Detach a telemetry handler.

  ## Examples

      TenantPlug.Telemetry.detach("my-handler")
  """
  @spec detach(String.t()) :: :ok | {:error, term()}
  def detach(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Get telemetry metadata template for a given event.

  ## Examples

      iex> TenantPlug.Telemetry.metadata_template(:tenant_resolved)
      %{tenant: nil, source: nil, conn: nil, opts: nil}
  """
  @spec metadata_template(atom()) :: map()
  def metadata_template(:tenant_resolved) do
    %{tenant: nil, source: nil, conn: nil, opts: nil}
  end

  def metadata_template(:tenant_cleared) do
    %{tenant: nil}
  end

  def metadata_template(:source_exception) do
    %{error: nil, source: nil, conn: nil, opts: nil}
  end

  def metadata_template(:source_error) do
    %{error: nil, conn: nil, opts: nil}
  end

  def metadata_template(:snapshot_created) do
    %{tenant: nil, snapshot: nil}
  end

  def metadata_template(:snapshot_applied) do
    %{tenant: nil, snapshot: nil}
  end

  def metadata_template(_), do: %{}

  @doc """
  Format telemetry event data for logging or debugging.

  ## Examples

      iex> event_data = %{tenant: "acme", source: MySource}
      iex> TenantPlug.Telemetry.format_event([:tenant_plug, :tenant, :resolved], %{count: 1}, event_data)
      "[tenant_plug.tenant.resolved] tenant=acme source=MySource count=1"
  """
  @spec format_event([atom()], map(), map()) :: String.t()
  def format_event(event_name, measurements, metadata) do
    event_str = Enum.join(event_name, ".")
    
    metadata_str = 
      metadata
      |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
      |> Enum.join(" ")
    
    measurements_str =
      measurements
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(" ")
    
    "[#{event_str}] #{metadata_str} #{measurements_str}"
  end
end