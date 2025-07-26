# frozen_string_literal: true

require "spec_helper"
require "cli_visualizer/audio/buffer"

RSpec.describe CliVisualizer::Audio::Buffer do
  let(:capacity) { 1024 }
  let(:sample_rate) { 44_100 }
  let(:channels) { 2 }
  let(:buffer) { described_class.new(capacity: capacity, sample_rate: sample_rate, channels: channels) }

  describe "#initialize" do
    it "creates buffer with specified parameters" do
      expect(buffer.capacity).to eq(capacity)
      expect(buffer.sample_rate).to eq(sample_rate)
      expect(buffer.channels).to eq(channels)
      expect(buffer.size).to eq(0)
      expect(buffer.status).to eq(described_class::STATUS_HEALTHY)
    end

    it "initializes statistics counters" do
      expect(buffer.overrun_count).to eq(0)
      expect(buffer.underrun_count).to eq(0)
      expect(buffer.total_written).to eq(0)
      expect(buffer.total_read).to eq(0)
    end
  end

  describe "#write and #read" do
    let(:test_samples) { [0.1, 0.2, 0.3, 0.4, 0.5] }

    it "writes and reads samples correctly" do
      written = buffer.write(test_samples)
      expect(written).to eq(test_samples.length)
      expect(buffer.size).to eq(test_samples.length)

      read_samples = buffer.read(test_samples.length)
      expect(read_samples).to eq(test_samples)
      expect(buffer.size).to eq(0)
    end

    it "handles partial writes when buffer gets full" do
      large_samples = Array.new(capacity + 100, 0.5)
      written = buffer.write(large_samples)

      # Buffer handles overruns by dropping old samples, so can write more than capacity
      expect(written).to be > capacity
      expect(buffer.size).to eq(capacity) # But size is capped at capacity
      expect(buffer.full?).to be true
      expect(buffer.overrun_count).to be > 0 # Should trigger overruns
    end

    it "handles partial reads when buffer empties" do
      buffer.write([0.1, 0.2, 0.3])
      read_samples = buffer.read(10) # Request more than available

      expect(read_samples.length).to eq(3)
      expect(buffer.empty?).to be true
    end

    it "updates statistics correctly" do
      buffer.write([0.1, 0.2])
      buffer.read(1)

      expect(buffer.total_written).to eq(2)
      expect(buffer.total_read).to eq(1)
    end
  end

  describe "#peek" do
    it "returns samples without removing them" do
      test_samples = [0.1, 0.2, 0.3]
      buffer.write(test_samples)

      peeked = buffer.peek(2)
      expect(peeked).to eq([0.1, 0.2])
      expect(buffer.size).to eq(3) # Still contains all samples

      read_samples = buffer.read(3)
      expect(read_samples).to eq(test_samples)
    end

    it "handles peek requests larger than buffer content" do
      buffer.write([0.1, 0.2])
      peeked = buffer.peek(10)

      expect(peeked.length).to eq(2)
      expect(peeked).to eq([0.1, 0.2])
    end
  end

  describe "buffer state queries" do
    it "reports empty state correctly" do
      expect(buffer.empty?).to be true
      expect(buffer.full?).to be false

      buffer.write([0.1])
      expect(buffer.empty?).to be false
    end

    it "reports full state correctly" do
      buffer.write(Array.new(capacity, 0.5))
      expect(buffer.full?).to be true
      expect(buffer.empty?).to be false
    end

    it "calculates utilization correctly" do
      expect(buffer.utilization).to eq(0.0)

      buffer.write(Array.new(capacity / 2, 0.5))
      expect(buffer.utilization).to be_within(0.01).of(0.5)

      buffer.write(Array.new(capacity / 2, 0.5))
      expect(buffer.utilization).to be_within(0.01).of(1.0)
    end
  end

  describe "overrun handling" do
    it "handles buffer overruns gracefully" do
      # Fill buffer to capacity
      buffer.write(Array.new(capacity, 0.5))
      expect(buffer.full?).to be true

      # Try to write more - should trigger overrun
      additional_samples = [0.1, 0.2, 0.3]
      buffer.write(additional_samples)

      expect(buffer.overrun_count).to be > 0
      expect(buffer.status).to eq(described_class::STATUS_OVERRUN)
    end

    it "maintains buffer integrity during overruns" do
      # Fill buffer
      original_samples = Array.new(capacity, 0.7)
      buffer.write(original_samples)

      # Cause overrun
      buffer.write([0.1, 0.2])

      # Buffer should still be readable
      expect(buffer.size).to be <= capacity
      read_samples = buffer.read(buffer.size)
      expect(read_samples).to all(be_a(Float))
    end
  end

  describe "underrun handling" do
    it "handles buffer underruns gracefully" do
      # Try to read from empty buffer
      read_samples = buffer.read(10)

      expect(read_samples).to be_empty
      expect(buffer.underrun_count).to be > 0
      expect(buffer.status).to eq(described_class::STATUS_UNDERRUN)
    end

    it "recovers from underrun when data is available" do
      buffer.read(5) # Cause underrun
      expect(buffer.status).to eq(described_class::STATUS_UNDERRUN)

      # Add data and read normally
      buffer.write([0.1, 0.2, 0.3])
      read_samples = buffer.read(2)

      expect(read_samples).to eq([0.1, 0.2])
    end
  end

  describe "timeout operations" do
    it "respects write timeouts" do
      # Fill buffer first
      buffer.write(Array.new(capacity, 0.5))

      start_time = Time.now
      written = buffer.write([0.1, 0.2], timeout: 0.1)
      elapsed = Time.now - start_time

      expect(elapsed).to be < 0.2 # Should timeout quickly
      expect(written).to be < 2   # Shouldn't write everything
    end

    it "respects read timeouts" do
      start_time = Time.now
      read_samples = buffer.read(10, timeout: 0.1)
      elapsed = Time.now - start_time

      expect(elapsed).to be < 0.2 # Should timeout quickly
      expect(read_samples).to be_empty
    end
  end

  describe "thread safety" do
    it "handles concurrent reads and writes safely" do
      results = []
      threads = []

      # Writer thread
      threads << Thread.new do
        1000.times do |i|
          buffer.write([i.to_f])
          sleep(0.001)
        end
      end

      # Reader thread
      threads << Thread.new do
        1000.times do
          samples = buffer.read(1)
          results.concat(samples)
          sleep(0.001)
        end
      end

      threads.each(&:join)

      # Should have read some samples without errors
      expect(results).not_to be_empty
      expect(results).to all(be_a(Float))
    end

    it "maintains data integrity under concurrent access" do
      test_data = (1..100).to_a.map(&:to_f)
      read_results = []

      # Multiple writer threads
      writers = 3.times.map do |thread_id|
        Thread.new do
          test_data.each { |sample| buffer.write([sample + (thread_id * 1000)]) }
        end
      end

      # Multiple reader threads
      readers = 2.times.map do
        Thread.new do
          while writers.any?(&:alive?) || !buffer.empty?
            samples = buffer.read(10)
            read_results.concat(samples)
            sleep(0.001)
          end
        end
      end

      (writers + readers).each(&:join)

      # All data should be valid floats
      expect(read_results).to all(be_a(Float))
      expect(read_results.length).to be > 0
    end
  end

  describe "utility methods" do
    it "clears buffer correctly" do
      buffer.write([0.1, 0.2, 0.3])
      expect(buffer.size).to eq(3)

      buffer.clear
      expect(buffer.size).to eq(0)
      expect(buffer.empty?).to be true
      expect(buffer.status).to eq(described_class::STATUS_HEALTHY)
    end

    it "resets statistics correctly" do
      buffer.write([0.1, 0.2])
      buffer.read(1)
      buffer.write(Array.new(capacity + 1, 0.5)) # Cause overrun

      expect(buffer.total_written).to be > 0
      expect(buffer.overrun_count).to be > 0

      buffer.reset_stats
      expect(buffer.total_written).to eq(0)
      expect(buffer.total_read).to eq(0)
      expect(buffer.overrun_count).to eq(0)
      expect(buffer.underrun_count).to eq(0)
    end
  end

  describe "statistics and monitoring" do
    it "provides comprehensive statistics" do
      buffer.write([0.1, 0.2, 0.3])
      buffer.read(1)

      stats = buffer.stats
      expect(stats).to include(
        :capacity, :size, :utilization, :status,
        :overrun_count, :underrun_count, :total_written, :total_read,
        :write_rate, :read_rate, :latency_samples, :latency_ms
      )

      expect(stats[:capacity]).to eq(capacity)
      expect(stats[:size]).to eq(2)
      expect(stats[:utilization]).to be_within(0.01).of(2.0 / capacity)
    end

    it "calculates latency correctly" do
      samples_count = 100
      buffer.write(Array.new(samples_count, 0.5))

      stats = buffer.stats
      expected_latency_ms = (samples_count.to_f / sample_rate) * 1000

      expect(stats[:latency_samples]).to eq(samples_count)
      expect(stats[:latency_ms]).to be_within(0.1).of(expected_latency_ms)
    end

    it "reports healthy status for normal operations" do
      buffer.write([0.1, 0.2])
      buffer.read(1)

      expect(buffer.healthy?).to be true
      expect(buffer.stats[:status]).to eq(described_class::STATUS_HEALTHY)
    end
  end

  describe "class methods" do
    describe ".size_for_latency" do
      it "calculates correct buffer size for target latency" do
        latency_ms = 50
        target_size = described_class.size_for_latency(latency_ms, sample_rate, channels)

        expected_samples_per_channel = (latency_ms / 1000.0 * sample_rate).ceil
        expected_total = expected_samples_per_channel * channels

        expect(target_size).to eq(expected_total)
      end
    end

    describe ".duration_for_samples" do
      it "calculates duration correctly" do
        samples = 4410 # 0.1 seconds worth at 44.1kHz
        duration = described_class.duration_for_samples(samples, sample_rate)

        expect(duration).to be_within(0.001).of(0.1)
      end
    end
  end

  describe "performance characteristics" do
    it "handles large buffers efficiently" do
      large_buffer = described_class.new(capacity: 100_000, sample_rate: sample_rate)
      large_data = Array.new(50_000) { rand(-1.0..1.0) }

      start_time = Time.now
      written = large_buffer.write(large_data)
      write_time = Time.now - start_time

      start_time = Time.now
      read_data = large_buffer.read(written)
      read_time = Time.now - start_time

      # Should complete quickly (less than 100ms each)
      expect(write_time).to be < 0.1
      expect(read_time).to be < 0.1
      expect(read_data.length).to eq(written)
    end
  end
end
