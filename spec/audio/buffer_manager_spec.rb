# frozen_string_literal: true

require "spec_helper"
require "cli_visualizer/audio/buffer_manager"

RSpec.describe CliVisualizer::Audio::BufferManager do
  let(:sample_rate) { 44_100 }
  let(:channels) { 2 }
  let(:manager) { described_class.new(sample_rate: sample_rate, channels: channels) }

  describe "#initialize" do
    it "creates manager with specified parameters" do
      expect(manager.sample_rate).to eq(sample_rate)
      expect(manager.channels).to eq(channels)
      expect(manager.buffers).to be_empty
    end

    it "calculates buffer size from target latency" do
      custom_manager = described_class.new(
        sample_rate: 48_000,
        channels: 2,
        target_latency_ms: 100
      )

      # Should create buffers with appropriate size for 100ms latency
      custom_manager.create_buffer("test")
      buffer = custom_manager.get_buffer("test")

      expect(buffer.capacity).to be > 4800 # 100ms at 48kHz stereo
    end
  end

  describe "buffer management" do
    it "creates and retrieves buffers" do
      manager.create_buffer("audio_in")
      buffer = manager.get_buffer("audio_in")

      expect(buffer).to be_a(CliVisualizer::Audio::Buffer)
      expect(buffer.sample_rate).to eq(sample_rate)
      expect(buffer.channels).to eq(channels)
    end

    it "creates buffers with custom capacity" do
      custom_capacity = 2048
      manager.create_buffer("large_buffer", capacity: custom_capacity)
      buffer = manager.get_buffer("large_buffer")

      expect(buffer.capacity).to eq(custom_capacity)
    end

    it "removes buffers correctly" do
      manager.create_buffer("temp_buffer")
      expect(manager.get_buffer("temp_buffer")).not_to be_nil

      removed_buffer = manager.remove_buffer("temp_buffer")
      expect(removed_buffer).to be_a(CliVisualizer::Audio::Buffer)
      expect(manager.get_buffer("temp_buffer")).to be_nil
    end

    it "handles non-existent buffer requests" do
      expect(manager.get_buffer("nonexistent")).to be_nil
      expect(manager.remove_buffer("nonexistent")).to be_nil
    end
  end

  describe "buffer I/O operations" do
    before do
      manager.create_buffer("test_buffer", capacity: 1024)
    end

    let(:test_samples) { [0.1, 0.2, 0.3, 0.4, 0.5] }

    it "writes to and reads from buffers" do
      written = manager.write_to_buffer("test_buffer", test_samples)
      expect(written).to eq(test_samples.length)

      read_samples = manager.read_from_buffer("test_buffer", test_samples.length)
      expect(read_samples).to eq(test_samples)
    end

    it "handles writes to non-existent buffers" do
      written = manager.write_to_buffer("nonexistent", test_samples)
      expect(written).to eq(0)
    end

    it "handles reads from non-existent buffers" do
      read_samples = manager.read_from_buffer("nonexistent", 10)
      expect(read_samples).to be_empty
    end
  end

  describe "routing system" do
    before do
      manager.create_buffer("source_buffer", capacity: 1024)
    end

    it "routes data to registered consumers" do
      received_data = []

      manager.route("source_buffer") do |samples|
        received_data.concat(samples)
      end

      test_samples = [0.1, 0.2, 0.3]
      manager.write_to_buffer("source_buffer", test_samples)

      expect(received_data).to eq(test_samples)
    end

    it "supports multiple consumers for the same buffer" do
      consumer1_data = []
      consumer2_data = []

      manager.route("source_buffer") { |samples| consumer1_data.concat(samples) }
      manager.route("source_buffer") { |samples| consumer2_data.concat(samples) }

      test_samples = [0.1, 0.2, 0.3]
      manager.write_to_buffer("source_buffer", test_samples)

      expect(consumer1_data).to eq(test_samples)
      expect(consumer2_data).to eq(test_samples)
    end

    it "provides isolated data copies to each consumer" do
      consumer1_data = []
      consumer2_data = []

      manager.route("source_buffer") do |samples|
        consumer1_data = samples
        samples[0] = 999.0 # Modify the array
      end

      manager.route("source_buffer") do |samples|
        consumer2_data = samples
      end

      manager.write_to_buffer("source_buffer", [0.1, 0.2])

      # Consumer 2 should not see consumer 1's modifications
      expect(consumer1_data[0]).to eq(999.0)
      expect(consumer2_data[0]).to eq(0.1)
    end

    it "clears routing correctly" do
      received_data = []
      manager.route("source_buffer") { |samples| received_data.concat(samples) }

      manager.clear_routes("source_buffer")
      manager.write_to_buffer("source_buffer", [0.1, 0.2])

      expect(received_data).to be_empty
    end

    it "handles routing errors gracefully" do
      manager.route("source_buffer") { |_| raise StandardError, "Consumer error" }

      # Should not raise error
      expect do
        manager.write_to_buffer("source_buffer", [0.1, 0.2])
      end.not_to raise_error
    end
  end

  describe "source and consumer interfaces" do
    describe "BufferedSource" do
      let(:source) { manager.create_source("audio_source") }

      it "provides source interface for writing" do
        written = source.write([0.1, 0.2, 0.3])
        expect(written).to eq(3)

        buffer = manager.get_buffer("audio_source")
        expect(buffer.size).to eq(3)
      end

      it "provides source statistics and health" do
        source.write([0.1, 0.2])

        expect(source.stats).to include(:capacity, :size, :utilization)
        expect(source.healthy?).to be true
      end

      it "can clear the underlying buffer" do
        source.write([0.1, 0.2, 0.3])
        source.clear

        expect(source.stats[:size]).to eq(0)
      end
    end

    describe "BufferedConsumer" do
      let(:consumer) do
        cons = manager.create_consumer("audio_consumer")
        buffer = manager.get_buffer("audio_consumer")
        buffer.write([0.1, 0.2, 0.3, 0.4, 0.5])
        cons
      end

      it "provides consumer interface for reading" do
        samples = consumer.read(3)
        expect(samples).to eq([0.1, 0.2, 0.3])
      end

      it "provides peek functionality" do
        peeked = consumer.peek(2)
        expect(peeked).to eq([0.1, 0.2])

        # Data should still be there
        read_samples = consumer.read(2)
        expect(read_samples).to eq([0.1, 0.2])
      end

      it "supports route_to for automatic callback setup" do
        received_data = []
        consumer.route_to { |samples| received_data.concat(samples) }

        # Write to the consumer's buffer via manager
        manager.write_to_buffer("audio_consumer", [0.9, 0.8])

        expect(received_data).to eq([0.9, 0.8])
      end

      it "reports data availability correctly" do
        expect(consumer.data_available?).to be true

        consumer.read(10) # Read all data
        expect(consumer.data_available?).to be false
      end

      it "provides consumer statistics and health" do
        expect(consumer.stats).to include(:capacity, :size, :utilization)
        expect(consumer.healthy?).to be true
      end
    end
  end

  describe "statistics and monitoring" do
    before do
      manager.create_buffer("buffer1", capacity: 1000)
      manager.create_buffer("buffer2", capacity: 2000)

      # Add some data to create interesting statistics
      manager.write_to_buffer("buffer1", Array.new(500, 0.5))
      manager.write_to_buffer("buffer2", Array.new(1000, 0.3))
    end

    it "provides comprehensive system statistics" do
      stats = manager.stats

      expect(stats).to include(
        :buffer_count, :sample_rate, :channels, :target_latency_ms,
        :buffers, :total_overruns, :total_underruns,
        :average_utilization, :health_status
      )

      expect(stats[:buffer_count]).to eq(2)
      expect(stats[:sample_rate]).to eq(sample_rate)
      expect(stats[:channels]).to eq(channels)
      expect(stats[:buffers]).to have_key("buffer1")
      expect(stats[:buffers]).to have_key("buffer2")
    end

    it "calculates average utilization correctly" do
      stats = manager.stats

      # buffer1: 500/1000 = 0.5, buffer2: 1000/2000 = 0.5
      # Average: (0.5 + 0.5) / 2 = 0.5
      expect(stats[:average_utilization]).to be_within(0.01).of(0.5)
    end

    it "determines overall health status" do
      stats = manager.stats
      expect(stats[:health_status]).to eq(:healthy)

      # Cause some overruns
      manager.write_to_buffer("buffer1", Array.new(1000, 0.9)) # Should overrun

      stats = manager.stats
      expect(stats[:health_status]).to(satisfy { |status| %i[degraded unhealthy].include?(status) })
    end

    it "monitors health over time" do
      expect(manager.stats_history).to be_empty

      health_stats = manager.monitor_health
      expect(health_stats).to include(:buffer_count, :health_status) # Current stats
      expect(manager.stats_history.length).to eq(1)
      expect(manager.stats_history.first).to include(:timestamp) # History has timestamp

      # Monitor again
      manager.monitor_health
      expect(manager.stats_history.length).to eq(2)
    end

    it "maintains limited history" do
      # Simulate old history
      61.times do |i|
        manager.instance_variable_get(:@stats_history) << {
          timestamp: Time.now - (70 - i),
          buffer_count: 1
        }
      end

      # Should clean up old entries
      manager.monitor_health
      history = manager.stats_history

      expect(history.length).to be < 61
      expect(history.all? { |entry| entry[:timestamp] > Time.now - 60 }).to be true
    end
  end

  describe "bulk operations" do
    before do
      manager.create_buffer("buffer1")
      manager.create_buffer("buffer2")

      # Add data to buffers
      manager.write_to_buffer("buffer1", [0.1, 0.2])
      manager.write_to_buffer("buffer2", [0.3, 0.4])
    end

    it "clears all buffers" do
      manager.clear_all

      expect(manager.get_buffer("buffer1").empty?).to be true
      expect(manager.get_buffer("buffer2").empty?).to be true
    end

    it "resets all statistics" do
      # Generate some stats
      manager.read_from_buffer("buffer1", 1)

      initial_stats = manager.stats
      expect(initial_stats[:total_overruns] + initial_stats[:total_underruns]).to be >= 0

      manager.reset_all_stats

      reset_stats = manager.stats
      expect(reset_stats[:total_overruns]).to eq(0)
      expect(reset_stats[:total_underruns]).to eq(0)
    end
  end

  describe "recommended buffer sizes" do
    it "provides size recommendations for different latency targets" do
      recommendations = described_class.recommended_sizes(sample_rate, channels)

      expect(recommendations).to include(:low_latency, :normal, :high_latency, :safe)
      expect(recommendations[:low_latency]).to be < recommendations[:normal]
      expect(recommendations[:normal]).to be < recommendations[:high_latency]
      expect(recommendations[:high_latency]).to be < recommendations[:safe]
    end

    it "scales recommendations with sample rate" do
      low_rate_recs = described_class.recommended_sizes(22_050, 2)
      high_rate_recs = described_class.recommended_sizes(96_000, 2)

      expect(high_rate_recs[:normal]).to be > low_rate_recs[:normal]
    end
  end

  describe "integration scenarios" do
    it "handles producer-consumer pipeline" do
      # Set up pipeline: source -> buffer -> consumer
      source = manager.create_source("pipeline_input")
      consumer = manager.create_consumer("pipeline_output")

      # Route from input to output
      manager.route("pipeline_input") do |samples|
        manager.write_to_buffer("pipeline_output", samples)
      end

      # Producer writes data
      test_data = [0.1, 0.2, 0.3, 0.4, 0.5]
      source.write(test_data)

      # Consumer should be able to read it
      consumer_data = consumer.read(test_data.length)
      expect(consumer_data).to eq(test_data)
    end

    it "handles multiple producers to single consumer" do
      producer1 = manager.create_source("prod1")
      producer2 = manager.create_source("prod2")
      consumer = manager.create_consumer("mixer")

      mixed_data = []

      # Route both producers to consumer
      manager.route("prod1") { |samples| mixed_data.concat(samples.map { |s| s + 0.1 }) }
      manager.route("prod2") { |samples| mixed_data.concat(samples.map { |s| s + 0.2 }) }

      producer1.write([0.1, 0.2])
      producer2.write([0.3, 0.4])

      # Should have received modified data from both producers (allow floating point tolerance)
      expect(mixed_data.size).to eq(4)
      expect(mixed_data).to include(a_value_within(0.001).of(0.2))
      expect(mixed_data).to include(a_value_within(0.001).of(0.3))
      expect(mixed_data).to include(a_value_within(0.001).of(0.5))
      expect(mixed_data).to include(a_value_within(0.001).of(0.6))
    end

    it "handles concurrent access to shared buffers" do
      manager.create_buffer("shared", capacity: 10_000)

      # Multiple threads writing and reading concurrently
      threads = []
      results = []

      # Writer threads
      3.times do |writer_id|
        threads << Thread.new do
          100.times do |i|
            samples = [writer_id * 100 + i].map(&:to_f)
            manager.write_to_buffer("shared", samples)
            sleep(0.001)
          end
        end
      end

      # Reader threads
      2.times do
        threads << Thread.new do
          while threads.first(3).any?(&:alive?) || !manager.get_buffer("shared").empty?
            samples = manager.read_from_buffer("shared", 5)
            results.concat(samples)
            sleep(0.001)
          end
        end
      end

      threads.each(&:join)

      # Should have read some data without errors
      expect(results).not_to be_empty
      expect(results).to all(be_a(Float))
    end
  end
end
