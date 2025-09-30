defmodule TenantPlug.TelemetryTest do
  use ExUnit.Case, async: true

  alias TenantPlug.Telemetry

  setup do
    # Ensure we start with clean telemetry state
    :telemetry.detach("test_handler")
    :ok
  end

  describe "tenant_resolved/2" do
    test "emits tenant resolved event" do
      assert_telemetry_event([:tenant_plug, :tenant, :resolved], fn ->
        Telemetry.tenant_resolved("resolved-tenant", %{source: TestSource})
      end)
    end

    test "includes tenant in metadata" do
      {_event, _measurements, metadata} = capture_telemetry_event([:tenant_plug, :tenant, :resolved], fn ->
        Telemetry.tenant_resolved("metadata-tenant", %{extra: "data"})
      end)
      
      assert metadata.tenant == "metadata-tenant"
      assert metadata.extra == "data"
    end
  end

  describe "tenant_cleared/1" do
    test "emits tenant cleared event" do
      assert_telemetry_event([:tenant_plug, :tenant, :cleared], fn ->
        Telemetry.tenant_cleared(%{tenant: "cleared-tenant"})
      end)
    end
  end

  describe "source_exception/2" do
    test "emits source exception event" do
      error = %RuntimeError{message: "Test error"}
      
      assert_telemetry_event([:tenant_plug, :error, :source_exception], fn ->
        Telemetry.source_exception(error, %{source: TestSource})
      end)
    end

    test "includes error in metadata" do
      error = %RuntimeError{message: "Exception error"}
      
      {_event, _measurements, metadata} = capture_telemetry_event([:tenant_plug, :error, :source_exception], fn ->
        Telemetry.source_exception(error, %{source: TestSource})
      end)
      
      assert metadata.error == error
      assert metadata.source == TestSource
    end
  end

  describe "source_error/2" do
    test "emits source error event" do
      assert_telemetry_event([:tenant_plug, :error, :source_error], fn ->
        Telemetry.source_error("Error message", %{context: "test"})
      end)
    end

    test "includes error in metadata" do
      {_event, _measurements, metadata} = capture_telemetry_event([:tenant_plug, :error, :source_error], fn ->
        Telemetry.source_error("Custom error", %{context: "test"})
      end)
      
      assert metadata.error == "Custom error"
      assert metadata.context == "test"
    end
  end

  describe "snapshot_created/1" do
    test "emits snapshot created event" do
      assert_telemetry_event([:tenant_plug, :context, :snapshot_created], fn ->
        Telemetry.snapshot_created(%{tenant: "snapshot-tenant"})
      end)
    end
  end

  describe "snapshot_applied/1" do
    test "emits snapshot applied event" do
      assert_telemetry_event([:tenant_plug, :context, :snapshot_applied], fn ->
        Telemetry.snapshot_applied(%{tenant: "applied-tenant"})
      end)
    end
  end

  describe "measure/3" do
    test "measures function execution time" do
      {event, measurements, metadata} = capture_telemetry_event([:test, :measure], fn ->
        Telemetry.measure([:test, :measure], %{context: "test"}, fn ->
          :timer.sleep(10)
          "result"
        end)
      end)
      
      assert event == [:test, :measure]
      assert measurements.count == 1
      assert measurements.duration > 0
      assert metadata.result == :ok
      assert metadata.context == "test"
    end

    test "measures function execution time on error" do
      {_event, measurements, metadata} = capture_telemetry_event([:test, :measure_error], fn ->
        assert_raise RuntimeError, fn ->
          Telemetry.measure([:test, :measure_error], %{}, fn ->
            raise "Test error"
          end)
        end
      end)
      
      assert measurements.count == 1
      assert measurements.duration > 0
      assert metadata.result == :error
      assert %RuntimeError{} = metadata.error
    end
  end

  describe "span/3" do
    test "emits start and stop events" do
      events = capture_multiple_events([[:test, :span, :start], [:test, :span, :stop]], fn ->
        Telemetry.span([:test, :span], %{operation: "test"}, fn ->
          :timer.sleep(10)
          "span-result"
        end)
      end)
      
      assert length(events) == 2
      
      start_event = Enum.find(events, fn {event, _, _} -> event == [:test, :span, :start] end)
      stop_event = Enum.find(events, fn {event, _, _} -> event == [:test, :span, :stop] end)
      
      {_event, start_measurements, start_metadata} = start_event
      assert start_measurements.count == 1
      assert is_integer(start_measurements.monotonic_time)
      assert start_metadata.operation == "test"
      assert is_reference(start_metadata.span_id)
      
      {_event, stop_measurements, stop_metadata} = stop_event
      assert stop_measurements.count == 1
      assert stop_measurements.duration > 0
      assert stop_metadata.result == :ok
      assert stop_metadata.operation == "test"
    end

    test "emits stop event on error" do
      events = capture_multiple_events([[:test, :span_error, :start], [:test, :span_error, :stop]], fn ->
        assert_raise RuntimeError, fn ->
          Telemetry.span([:test, :span_error], %{}, fn ->
            raise "Span error"
          end)
        end
      end)
      
      assert length(events) == 2
      
      start_event = Enum.find(events, fn {event, _, _} -> event == [:test, :span_error, :start] end)
      stop_event = Enum.find(events, fn {event, _, _} -> event == [:test, :span_error, :stop] end)
      
      {_event, _start_measurements, _start_metadata} = start_event
      
      {_event, stop_measurements, stop_metadata} = stop_event
      assert stop_measurements.count == 1
      assert stop_measurements.duration > 0
      assert stop_metadata.result == :error
      assert %RuntimeError{} = stop_metadata.error
    end
  end

  describe "events/0" do
    test "returns list of all events" do
      events = Telemetry.events()
      
      assert [:tenant_plug, :tenant, :resolved] in events
      assert [:tenant_plug, :tenant, :cleared] in events
      assert [:tenant_plug, :error, :source_exception] in events
      assert [:tenant_plug, :error, :source_error] in events
      assert [:tenant_plug, :context, :snapshot_created] in events
      assert [:tenant_plug, :context, :snapshot_applied] in events
    end
  end

  describe "attach_all/3 and detach/1" do
    test "attaches handler for all events" do
      test_pid = self()
      
      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end
      
      assert :ok = Telemetry.attach_all("test_handler", handler, %{})
      
      # Emit an event and verify it's received
      Telemetry.tenant_resolved("attach-test", %{})
      
      assert_receive {:telemetry, [:tenant_plug, :tenant, :resolved], measurements, metadata}
      assert measurements.count == 1
      assert metadata.tenant == "attach-test"
      
      # Clean up
      assert :ok = Telemetry.detach("test_handler")
    end

    test "detach removes handler" do
      test_pid = self()
      
      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end
      
      Telemetry.attach_all("detach_test", handler, %{})
      Telemetry.detach("detach_test")
      
      # Emit event after detaching
      Telemetry.tenant_resolved("detach-test", %{})
      
      # Should not receive the event
      refute_receive {:telemetry, _, _, _}, 100
    end
  end

  describe "metadata_template/1" do
    test "returns template for tenant_resolved" do
      template = Telemetry.metadata_template(:tenant_resolved)
      
      assert Map.has_key?(template, :tenant)
      assert Map.has_key?(template, :source)
      assert Map.has_key?(template, :conn)
      assert Map.has_key?(template, :opts)
    end

    test "returns template for tenant_cleared" do
      template = Telemetry.metadata_template(:tenant_cleared)
      
      assert Map.has_key?(template, :tenant)
    end

    test "returns template for source_exception" do
      template = Telemetry.metadata_template(:source_exception)
      
      assert Map.has_key?(template, :error)
      assert Map.has_key?(template, :source)
    end

    test "returns empty map for unknown event" do
      template = Telemetry.metadata_template(:unknown_event)
      assert template == %{}
    end
  end

  describe "format_event/3" do
    test "formats telemetry event data" do
      event = [:tenant_plug, :tenant, :resolved]
      measurements = %{count: 1, duration: 1000}
      metadata = %{tenant: "test-tenant", source: TestSource}
      
      formatted = Telemetry.format_event(event, measurements, metadata)
      
      assert String.contains?(formatted, "tenant_plug.tenant.resolved")
      assert String.contains?(formatted, "tenant=\"test-tenant\"")
      assert String.contains?(formatted, "count=1")
      assert String.contains?(formatted, "duration=1000")
    end

    test "handles empty metadata and measurements" do
      event = [:test, :event]
      measurements = %{}
      metadata = %{}
      
      formatted = Telemetry.format_event(event, measurements, metadata)
      
      assert String.contains?(formatted, "test.event")
    end
  end

  # Helper functions for testing telemetry events
  defp assert_telemetry_event(expected_event, fun) do
    {event, _measurements, _metadata} = capture_telemetry_event(expected_event, fun)
    assert event == expected_event
  end

  defp capture_telemetry_event(event_name, fun) do
    test_pid = self()
    
    handler = fn event, measurements, metadata, _config ->
      if event == event_name do
        send(test_pid, {:captured_event, event, measurements, metadata})
      end
    end
    
    :telemetry.attach("capture_handler", event_name, handler, %{})
    
    try do
      fun.()
      
      receive do
        {:captured_event, event, measurements, metadata} ->
          {event, measurements, metadata}
      after
        1000 ->
          raise "Expected telemetry event #{inspect(event_name)} was not emitted"
      end
    after
      :telemetry.detach("capture_handler")
    end
  end

  defp capture_multiple_events(event_names, fun) when is_list(event_names) do
    test_pid = self()
    
    handler = fn event, measurements, metadata, _config ->
      if event in event_names do
        send(test_pid, {:captured_event, event, measurements, metadata})
      end
    end
    
    :telemetry.attach_many("multi_capture_handler", event_names, handler, %{})
    
    try do
      fun.()
      collect_events(length(event_names), [])
    after
      :telemetry.detach("multi_capture_handler")
    end
  end

  defp collect_events(0, acc), do: Enum.reverse(acc)
  
  defp collect_events(remaining, acc) when remaining > 0 do
    receive do
      {:captured_event, event, measurements, metadata} ->
        collect_events(remaining - 1, [{event, measurements, metadata} | acc])
    after
      1000 ->
        raise "Expected #{remaining} more telemetry events but they were not emitted"
    end
  end
end