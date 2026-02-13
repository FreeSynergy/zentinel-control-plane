defmodule SentinelCp.Observability.Tracer do
  @moduledoc """
  Telemetry-based tracing for key control plane operations.

  Wraps `:telemetry` to emit span events for bundle compilation,
  rollout lifecycle, webhook processing, and node heartbeats.
  Compatible with OpenTelemetry exporters when OTEL SDK is configured.
  """

  require Logger

  @doc """
  Executes a function within a traced span.

  Emits `[:sentinel_cp, span_name, :start]` and `[:sentinel_cp, span_name, :stop]`
  telemetry events with timing metadata.
  """
  def span(span_name, metadata, fun) when is_atom(span_name) and is_map(metadata) do
    start_time = System.monotonic_time()
    trace_id = generate_trace_id()

    :telemetry.execute(
      [:sentinel_cp, span_name, :start],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{trace_id: trace_id})
    )

    try do
      result = fun.()

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:sentinel_cp, span_name, :stop],
        %{duration: duration},
        Map.merge(metadata, %{trace_id: trace_id, result: :ok})
      )

      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:sentinel_cp, span_name, :exception],
          %{duration: duration},
          Map.merge(metadata, %{
            trace_id: trace_id,
            kind: :error,
            reason: Exception.message(e),
            stacktrace: __STACKTRACE__
          })
        )

        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Wraps a bundle compilation pipeline with tracing spans.
  """
  def trace_compilation(bundle_id, fun) do
    span(:bundle_compilation, %{bundle_id: bundle_id}, fun)
  end

  @doc """
  Wraps a rollout tick with tracing spans.
  """
  def trace_rollout_tick(rollout_id, fun) do
    span(:rollout_tick, %{rollout_id: rollout_id}, fun)
  end

  @doc """
  Wraps webhook processing with tracing spans.
  """
  def trace_webhook(provider, fun) do
    span(:webhook_processing, %{provider: provider}, fun)
  end

  @doc """
  Wraps node heartbeat processing with tracing spans.
  """
  def trace_heartbeat(node_id, fun) do
    span(:node_heartbeat, %{node_id: node_id}, fun)
  end

  @doc """
  Returns all telemetry event prefixes emitted by the tracer.
  """
  def event_prefixes do
    [
      [:sentinel_cp, :bundle_compilation],
      [:sentinel_cp, :rollout_tick],
      [:sentinel_cp, :webhook_processing],
      [:sentinel_cp, :node_heartbeat]
    ]
  end

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.hex_encode32(case: :lower, padding: false)
  end
end
