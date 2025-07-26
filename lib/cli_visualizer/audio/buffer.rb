# frozen_string_literal: true

module CliVisualizer
  module Audio
    # Thread-safe circular buffer for real-time audio processing
    # Provides efficient buffering with overrun/underrun detection
    class Buffer
      # Buffer health status
      STATUS_HEALTHY = :healthy
      STATUS_UNDERRUN = :underrun
      STATUS_OVERRUN = :overrun
      STATUS_ERROR = :error

      attr_reader :capacity, :sample_rate, :channels, :size, :status, :overrun_count, :underrun_count, :total_written,
                  :total_read

      def initialize(capacity:, sample_rate: 44_100, channels: 2)
        @capacity = capacity
        @sample_rate = sample_rate
        @channels = channels

        # Circular buffer storage
        @buffer = Array.new(@capacity, 0.0)
        @write_pos = 0
        @read_pos = 0
        @size = 0

        # Thread synchronization
        @mutex = Mutex.new
        @not_empty = ConditionVariable.new
        @not_full = ConditionVariable.new

        # Health monitoring
        @status = STATUS_HEALTHY
        @overrun_count = 0
        @underrun_count = 0
        @total_written = 0
        @total_read = 0
        @last_write_time = Time.now
        @last_read_time = Time.now
      end

      # Write audio samples to the buffer
      # Returns number of samples actually written
      def write(samples, timeout: nil)
        return 0 if samples.empty?

        @mutex.synchronize do
          samples_written = 0
          start_time = Time.now if timeout

          samples.each do |sample|
            # Check timeout
            break if timeout && (Time.now - start_time) > timeout

            # Wait for space if buffer is full
            while @size >= @capacity
              if timeout
                remaining_time = timeout - (Time.now - start_time)
                break if remaining_time <= 0

                @not_full.wait(@mutex, remaining_time)
              else
                # Handle overrun
                handle_overrun
                break
              end
            end

            # Write sample if there's space
            break unless @size < @capacity

            @buffer[@write_pos] = sample.to_f
            @write_pos = (@write_pos + 1) % @capacity
            @size += 1
            samples_written += 1
            @total_written += 1

            # Buffer full, couldn't write more
          end

          @last_write_time = Time.now
          @not_empty.signal if @size.positive?
          update_status

          samples_written
        end
      end

      # Read audio samples from the buffer
      # Returns array of samples, may be smaller than requested if buffer empties
      def read(count, timeout: nil)
        return [] if count <= 0

        @mutex.synchronize do
          samples_read = []
          start_time = Time.now if timeout

          count.times do
            # Check timeout
            break if timeout && (Time.now - start_time) > timeout

            # Wait for data if buffer is empty
            while @size.zero?
              if timeout
                remaining_time = timeout - (Time.now - start_time)
                break if remaining_time <= 0

                @not_empty.wait(@mutex, remaining_time)
              else
                # Handle underrun
                handle_underrun
                break
              end
            end

            # Read sample if available
            break unless @size.positive?

            sample = @buffer[@read_pos]
            @read_pos = (@read_pos + 1) % @capacity
            @size -= 1
            samples_read << sample
            @total_read += 1

            # Buffer empty, couldn't read more
          end

          @last_read_time = Time.now
          @not_full.signal if @size < @capacity
          update_status

          samples_read
        end
      end

      # Peek at samples without removing them from buffer
      def peek(count)
        @mutex.synchronize do
          return [] if @size.zero? || count <= 0

          available = [@size, count].min
          samples = []

          available.times do |i|
            pos = (@read_pos + i) % @capacity
            samples << @buffer[pos]
          end

          samples
        end
      end

      # Get current buffer utilization (0.0 to 1.0)
      def utilization
        @mutex.synchronize { @size.to_f / @capacity }
      end

      # Check if buffer is empty
      def empty?
        @mutex.synchronize { @size.zero? }
      end

      # Check if buffer is full
      def full?
        @mutex.synchronize { @size >= @capacity }
      end

      # Clear all data from buffer
      def clear
        @mutex.synchronize do
          @write_pos = 0
          @read_pos = 0
          @size = 0
          @status = STATUS_HEALTHY
          @not_full.broadcast
        end
      end

      # Reset statistics
      def reset_stats
        @mutex.synchronize do
          @overrun_count = 0
          @underrun_count = 0
          @total_written = 0
          @total_read = 0
          @last_write_time = Time.now
          @last_read_time = Time.now
        end
      end

      # Get buffer statistics
      def stats
        @mutex.synchronize do
          {
            capacity: @capacity,
            size: @size,
            utilization: @size.to_f / @capacity,
            status: @status,
            overrun_count: @overrun_count,
            underrun_count: @underrun_count,
            total_written: @total_written,
            total_read: @total_read,
            write_rate: calculate_write_rate,
            read_rate: calculate_read_rate,
            latency_samples: @size,
            latency_ms: (@size.to_f / @sample_rate) * 1000
          }
        end
      end

      # Get buffer health status
      def healthy?
        @status == STATUS_HEALTHY
      end

      # Calculate buffer duration in seconds
      def duration_seconds
        @mutex.synchronize { @size.to_f / @sample_rate }
      end

      # Calculate expected buffer duration for given sample count
      def self.duration_for_samples(samples, sample_rate)
        samples.to_f / sample_rate
      end

      # Calculate recommended buffer size for target latency
      def self.size_for_latency(latency_ms, sample_rate, channels = 2)
        samples_per_channel = (latency_ms / 1000.0 * sample_rate).ceil
        samples_per_channel * channels
      end

      private

      # Handle buffer overrun condition
      def handle_overrun
        @overrun_count += 1
        @status = STATUS_OVERRUN

        # For overrun, we could:
        # 1. Drop oldest samples (what we do here)
        # 2. Drop current write
        # 3. Expand buffer (if allowed)

        # Drop oldest sample to make room
        @read_pos = (@read_pos + 1) % @capacity
        @size -= 1 if @size.positive?
      end

      # Handle buffer underrun condition
      def handle_underrun
        @underrun_count += 1
        @status = STATUS_UNDERRUN
      end

      # Update buffer health status
      def update_status
        @status = if @overrun_count.positive? && (Time.now - @last_write_time) < 0.1
                    STATUS_OVERRUN
                  elsif @underrun_count.positive? && (Time.now - @last_read_time) < 0.1
                    STATUS_UNDERRUN
                  else
                    STATUS_HEALTHY
                  end
      end

      # Calculate approximate write rate (samples/second)
      def calculate_write_rate
        time_elapsed = Time.now - @last_write_time
        return 0.0 if time_elapsed <= 0 || @total_written.zero?

        # Estimate based on recent activity
        @sample_rate.to_f # Approximate, would need more sophisticated tracking
      end

      # Calculate approximate read rate (samples/second)
      def calculate_read_rate
        time_elapsed = Time.now - @last_read_time
        return 0.0 if time_elapsed <= 0 || @total_read.zero?

        # Estimate based on recent activity
        @sample_rate.to_f # Approximate, would need more sophisticated tracking
      end
    end
  end
end
