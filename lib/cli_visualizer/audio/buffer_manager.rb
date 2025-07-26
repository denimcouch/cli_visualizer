# frozen_string_literal: true

require_relative "buffer"

module CliVisualizer
  module Audio
    # Manages multiple audio buffers and provides routing between sources and consumers
    # Acts as a central hub for real-time audio processing pipeline
    class BufferManager
      # Default buffer configurations
      DEFAULT_BUFFER_SIZE = 8192  # Samples
      DEFAULT_TARGET_LATENCY = 50 # milliseconds

      attr_reader :buffers, :sample_rate, :channels

      def initialize(sample_rate: 44_100, channels: 2,
                     target_latency_ms: DEFAULT_TARGET_LATENCY)
        @sample_rate = sample_rate
        @channels = channels
        @target_latency_ms = target_latency_ms
        @buffer_size = Buffer.size_for_latency(target_latency_ms, sample_rate, channels)

        # Named buffers for different audio streams
        @buffers = {}
        @routes = {} # source_id => [consumer_callbacks]
        @mutex = Mutex.new

        # Monitoring
        @stats_history = []
        @last_stats_time = Time.now
      end

      # Create a new audio buffer with given name
      def create_buffer(name, capacity: nil, **options)
        @mutex.synchronize do
          capacity ||= @buffer_size

          @buffers[name] = Buffer.new(
            capacity: capacity,
            sample_rate: @sample_rate,
            channels: @channels,
            **options
          )
        end
      end

      # Get an existing buffer by name
      def get_buffer(name)
        @mutex.synchronize { @buffers[name] }
      end

      # Remove a buffer
      def remove_buffer(name)
        @mutex.synchronize do
          buffer = @buffers.delete(name)
          @routes.delete(name)
          buffer
        end
      end

      # Write audio data to a named buffer
      def write_to_buffer(buffer_name, samples, **options)
        buffer = get_buffer(buffer_name)
        return 0 unless buffer

        written = buffer.write(samples, **options)

        # Route data to consumers if configured
        route_data(buffer_name, samples) if written > 0

        written
      end

      # Read audio data from a named buffer
      def read_from_buffer(buffer_name, count, **options)
        buffer = get_buffer(buffer_name)
        return [] unless buffer

        buffer.read(count, **options)
      end

      # Set up routing from a buffer to consumer callbacks
      def route(buffer_name, &consumer_callback)
        @mutex.synchronize do
          @routes[buffer_name] ||= []
          @routes[buffer_name] << consumer_callback if consumer_callback
        end
      end

      # Remove all routes for a buffer
      def clear_routes(buffer_name)
        @mutex.synchronize do
          @routes[buffer_name] = []
        end
      end

      # Create a buffered audio source (producer) interface
      def create_source(name, buffer_size: nil)
        create_buffer(name, capacity: buffer_size)

        # Return a source interface
        BufferedSource.new(self, name)
      end

      # Create a buffered audio consumer (consumer) interface
      def create_consumer(name, buffer_size: nil)
        create_buffer(name, capacity: buffer_size)

        # Return a consumer interface
        BufferedConsumer.new(self, name)
      end

      # Get aggregated statistics for all buffers
      def stats
        @mutex.synchronize do
          buffer_stats = @buffers.transform_values(&:stats)

          {
            buffer_count: @buffers.size,
            sample_rate: @sample_rate,
            channels: @channels,
            target_latency_ms: @target_latency_ms,
            buffers: buffer_stats,
            total_overruns: buffer_stats.values.sum { |stats| stats[:overrun_count] },
            total_underruns: buffer_stats.values.sum { |stats| stats[:underrun_count] },
            average_utilization: calculate_average_utilization(buffer_stats),
            health_status: calculate_overall_health(buffer_stats)
          }
        end
      end

      # Monitor buffer health and collect statistics
      def monitor_health
        current_stats = stats
        @stats_history << current_stats.merge(timestamp: Time.now)

        # Keep only recent history (last 60 seconds)
        cutoff_time = Time.now - 60
        @stats_history.select! { |entry| entry[:timestamp] > cutoff_time }

        current_stats
      end

      # Get historical statistics
      def stats_history
        @stats_history.dup
      end

      # Clear all buffers
      def clear_all
        @mutex.synchronize do
          @buffers.each_value(&:clear)
        end
      end

      # Reset all statistics
      def reset_all_stats
        @mutex.synchronize do
          @buffers.each_value(&:reset_stats)
          @stats_history.clear
        end
      end

      # Get recommended buffer sizes for different latency targets
      def self.recommended_sizes(sample_rate, channels = 2)
        {
          low_latency: Buffer.size_for_latency(20, sample_rate, channels),    # 20ms
          normal: Buffer.size_for_latency(50, sample_rate, channels),         # 50ms
          high_latency: Buffer.size_for_latency(100, sample_rate, channels),  # 100ms
          safe: Buffer.size_for_latency(200, sample_rate, channels)           # 200ms
        }
      end

      private

      # Route audio data to registered consumers
      def route_data(buffer_name, samples)
        consumers = @routes[buffer_name]
        return unless consumers

        consumers.each do |callback|
          callback.call(samples.dup) # Give each consumer a copy
        rescue StandardError => e
          warn "Buffer routing error for #{buffer_name}: #{e.message}" if $VERBOSE
        end
      end

      # Calculate average buffer utilization
      def calculate_average_utilization(buffer_stats)
        return 0.0 if buffer_stats.empty?

        total_utilization = buffer_stats.values.sum { |stats| stats[:utilization] }
        total_utilization / buffer_stats.size
      end

      # Calculate overall system health status
      def calculate_overall_health(buffer_stats)
        return :unknown if buffer_stats.empty?

        unhealthy_count = buffer_stats.values.count do |stats|
          stats[:status] != Buffer::STATUS_HEALTHY
        end

        if unhealthy_count == 0
          :healthy
        elsif unhealthy_count < buffer_stats.size / 2
          :degraded
        else
          :unhealthy
        end
      end
    end

    # Producer interface for writing to a managed buffer
    class BufferedSource
      def initialize(manager, buffer_name)
        @manager = manager
        @buffer_name = buffer_name
      end

      # Write samples to the managed buffer
      def write(samples, **options)
        @manager.write_to_buffer(@buffer_name, samples, **options)
      end

      # Get buffer statistics
      def stats
        buffer = @manager.get_buffer(@buffer_name)
        buffer&.stats || {}
      end

      # Check if buffer is healthy
      def healthy?
        buffer = @manager.get_buffer(@buffer_name)
        buffer&.healthy? || false
      end

      # Clear the buffer
      def clear
        buffer = @manager.get_buffer(@buffer_name)
        buffer&.clear
      end
    end

    # Consumer interface for reading from a managed buffer
    class BufferedConsumer
      def initialize(manager, buffer_name)
        @manager = manager
        @buffer_name = buffer_name
      end

      # Read samples from the managed buffer
      def read(count, **options)
        @manager.read_from_buffer(@buffer_name, count, **options)
      end

      # Peek at samples without consuming them
      def peek(count)
        buffer = @manager.get_buffer(@buffer_name)
        buffer&.peek(count) || []
      end

      # Set up automatic routing to a callback
      def route_to(&callback)
        @manager.route(@buffer_name, &callback)
      end

      # Get buffer statistics
      def stats
        buffer = @manager.get_buffer(@buffer_name)
        buffer&.stats || {}
      end

      # Check if buffer is healthy
      def healthy?
        buffer = @manager.get_buffer(@buffer_name)
        buffer&.healthy? || false
      end

      # Check if data is available
      def data_available?
        buffer = @manager.get_buffer(@buffer_name)
        buffer && !buffer.empty?
      end
    end
  end
end
