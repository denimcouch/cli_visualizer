# frozen_string_literal: true

require "spec_helper"
require "cli_visualizer/audio/source_manager"
require "cli_visualizer/audio/processor"
require "tempfile"

RSpec.describe CliVisualizer::Audio::SourceManager, :integration do
  let(:manager) { described_class.new }
  let(:processor) { CliVisualizer::Audio::Processor.new }

  describe "complete audio pipeline integration" do
    let(:temp_audio_file1) { create_test_audio_file("test1") }
    let(:temp_audio_file2) { create_test_audio_file("test2") }

    before do
      # Create multiple audio sources
      manager.create_source("file1", type: :file, file_path: temp_audio_file1.path)
      manager.create_source("file2", type: :file, file_path: temp_audio_file2.path)
    end

    after do
      cleanup_temp_file(temp_audio_file1)
      cleanup_temp_file(temp_audio_file2)
    end

    it "integrates with audio processor for real-time analysis" do
      frequency_data_received = []

      # Set up processor to receive frequency analysis results
      processor.on_frequency_data do |result|
        frequency_data_received << result
      end

      # Connect source manager to processor
      manager.on_audio_data do |audio_samples|
        processor.process_samples(audio_samples)
      end

      # Switch to first source and simulate audio data
      manager.switch_to_source("file1")

      # Simulate audio data flowing through the pipeline
      test_samples = generate_test_audio_samples(1024)
      manager.buffer_manager.write_to_buffer("main_audio", test_samples)

      # Should have received frequency analysis data
      expect(frequency_data_received).not_to be_empty
      expect(frequency_data_received.first).to include(:frequencies, :magnitudes, :phases)
    end

    it "maintains audio continuity during source switches" do
      audio_chunks_received = []
      total_samples_received = 0

      # Track all audio data flowing through the system
      manager.on_audio_data do |samples|
        audio_chunks_received << samples.dup
        total_samples_received += samples.length
      end

      # Start with first source
      manager.switch_to_source("file1")
      simulate_audio_stream(manager, "main_audio", chunk_size: 512, chunk_count: 3)

      chunks_after_first = audio_chunks_received.length

      # Switch to second source
      manager.switch_to_source("file2")
      simulate_audio_stream(manager, "main_audio", chunk_size: 512, chunk_count: 3)

      # Should have received audio from both sources
      expect(audio_chunks_received.length).to be > chunks_after_first
      expect(total_samples_received).to be > 0
    end

    it "handles buffer management during source switching" do
      # Monitor buffer health during switches
      buffer_health_log = []

      # Set up monitoring
      monitoring_thread = Thread.new do
        10.times do
          stats = manager.buffer_manager.stats
          buffer_health_log << {
            timestamp: Time.now,
            health: stats[:health_status],
            utilization: stats[:average_utilization],
            switching: manager.switching?
          }
          sleep(0.05)
        end
      end

      # Perform multiple rapid switches
      3.times do |i|
        source_id = i.even? ? "file1" : "file2"
        manager.switch_to_source(source_id)
        simulate_audio_stream(manager, "main_audio", chunk_size: 256, chunk_count: 2)
        sleep(0.1)
      end

      monitoring_thread.join

      # Buffer should remain healthy throughout
      unhealthy_count = buffer_health_log.count { |entry| entry[:health] != :healthy }
      expect(unhealthy_count).to be < buffer_health_log.length / 2
    end

    it "provides comprehensive system statistics" do
      manager.switch_to_source("file1")
      manager.start

      # Simulate some activity
      simulate_audio_stream(manager, "main_audio", chunk_size: 1024, chunk_count: 2)

      # Switch sources
      manager.switch_to_source("file2")
      simulate_audio_stream(manager, "main_audio", chunk_size: 1024, chunk_count: 2)

      stats = manager.stats

      # Should have comprehensive statistics
      expect(stats).to include(
        :sources_created, :successful_switches, :current_source,
        :buffer_stats, :main_buffer_stats, :switch_count
      )

      expect(stats[:sources_created]).to eq(2)
      expect(stats[:successful_switches]).to be >= 2
      expect(stats[:switch_count]).to be >= 2
      expect(stats[:current_source][:type]).to eq(:file)

      # Buffer stats should be present
      expect(stats[:buffer_stats]).to include(:health_status, :average_utilization)
      expect(stats[:main_buffer_stats]).to include(:capacity, :size, :utilization)
    end
  end

  describe "error resilience and recovery" do
    it "recovers gracefully from source errors" do
      # Create a source that will fail
      begin
        manager.create_source("bad_source", type: :file, file_path: "/nonexistent/path.wav")
      rescue CliVisualizer::Audio::SourceError
        # Expected to fail
      end

      # Create a working source
      temp_file = create_test_audio_file("recovery_test")
      manager.create_source("good_source", type: :file, file_path: temp_file.path)

      # Should be able to use the working source
      expect(manager.switch_to_source("good_source")).to be true
      expect(manager.healthy?).to be true

      cleanup_temp_file(temp_file)
    end

    it "maintains buffer integrity during failed switches" do
      temp_file = create_test_audio_file("integrity_test")
      manager.create_source("working_source", type: :file, file_path: temp_file.path)

      # Start with working source
      manager.switch_to_source("working_source")
      initial_buffer_stats = manager.buffer_manager.stats

      # Try to switch to non-existent source
      manager.switch_to_source("nonexistent")

      # Buffer should still be intact
      final_buffer_stats = manager.buffer_manager.stats
      expect(final_buffer_stats[:health_status]).to eq(initial_buffer_stats[:health_status])

      cleanup_temp_file(temp_file)
    end
  end

  describe "performance characteristics" do
    it "handles rapid source switching efficiently" do
      # Create multiple sources
      temp_files = []
      5.times do |i|
        temp_file = create_test_audio_file("perf_test_#{i}")
        temp_files << temp_file
        manager.create_source("source_#{i}", type: :file, file_path: temp_file.path)
      end

      switch_times = []

      # Perform rapid switches and measure timing
      10.times do |i|
        source_id = "source_#{i % 5}"
        start_time = Time.now
        manager.switch_to_source(source_id)
        switch_time = Time.now - start_time
        switch_times << switch_time
      end

      # Switches should complete quickly (less than 100ms each)
      average_switch_time = switch_times.sum / switch_times.length
      expect(average_switch_time).to be < 0.1

      # Cleanup
      temp_files.each { |file| cleanup_temp_file(file) }
    end

    it "scales with multiple concurrent audio streams" do
      # Create multiple audio sources
      temp_files = []

      3.times do |i|
        temp_file = create_test_audio_file("concurrent_#{i}")
        temp_files << temp_file
        manager.create_source("concurrent_#{i}", type: :file, file_path: temp_file.path)
      end

      # Set up multiple processors
      processors = 3.times.map { CliVisualizer::Audio::Processor.new }
      results_received = Array.new(3) { [] }

      # Connect each processor to the source manager
      processors.each_with_index do |processor, index|
        processor.on_frequency_data do |result|
          results_received[index] << result
        end
      end

      # Single callback that fans out to multiple processors
      manager.on_audio_data do |samples|
        processors.each { |processor| processor.process_samples(samples) }
      end

      # Switch between sources and generate audio
      3.times do |i|
        manager.switch_to_source("concurrent_#{i}")
        simulate_audio_stream(manager, "main_audio", chunk_size: 512, chunk_count: 2)
      end

      # All processors should have received data
      results_received.each do |results|
        expect(results).not_to be_empty
      end

      # Cleanup
      temp_files.each { |file| cleanup_temp_file(file) }
    end
  end

  describe "real-world usage scenarios" do
    it "simulates visualizer switching between microphone and music file" do
      # Simulate microphone source (using file as mock)
      mic_file = create_test_audio_file("microphone_sim")
      manager.create_source("microphone", type: :file, file_path: mic_file.path)

      # Simulate music file
      music_file = create_test_audio_file("music_sim")
      manager.create_source("music", type: :file, file_path: music_file.path)

      visualization_data = []

      # Set up visualization pipeline
      manager.on_audio_data do |samples|
        # Simulate visualization processing
        visualization_data << {
          timestamp: Time.now,
          source: manager.current_source_info[:id],
          sample_count: samples.length,
          rms_level: calculate_rms(samples)
        }
      end

      # Start with microphone
      manager.switch_to_source("microphone")
      manager.start
      simulate_audio_stream(manager, "main_audio", chunk_size: 1024, chunk_count: 3)

      # Switch to music
      manager.switch_to_source("music")
      simulate_audio_stream(manager, "main_audio", chunk_size: 1024, chunk_count: 3)

      # Switch back to microphone
      manager.switch_to_source("microphone")
      simulate_audio_stream(manager, "main_audio", chunk_size: 1024, chunk_count: 3)

      # Should have visualization data from both sources
      mic_data = visualization_data.select { |entry| entry[:source] == "microphone" }
      music_data = visualization_data.select { |entry| entry[:source] == "music" }

      expect(mic_data).not_to be_empty
      expect(music_data).not_to be_empty
      expect(visualization_data.length).to be > 6

      cleanup_temp_file(mic_file)
      cleanup_temp_file(music_file)
    end
  end

  # Helper methods
  private

  def create_test_audio_file(name)
    temp_file = Tempfile.new(["#{name}_audio", ".wav"])
    # Create minimal WAV header
    temp_file.write("RIFF#{[44].pack("V")}WAVE")
    temp_file.close
    temp_file
  end

  def cleanup_temp_file(temp_file)
    temp_file&.unlink
  rescue StandardError
    # Ignore cleanup errors
  end

  def generate_test_audio_samples(count)
    # Generate simple sine wave samples
    Array.new(count) { |i| Math.sin(2 * Math::PI * i / 100.0) * 0.5 }
  end

  def simulate_audio_stream(manager, buffer_name, chunk_size: 1024, chunk_count: 1)
    chunk_count.times do
      samples = generate_test_audio_samples(chunk_size)
      manager.buffer_manager.write_to_buffer(buffer_name, samples)
      sleep(0.01) # Small delay to simulate real-time
    end
  end

  def calculate_rms(samples)
    return 0.0 if samples.empty?

    sum_of_squares = samples.sum { |sample| sample * sample }
    Math.sqrt(sum_of_squares / samples.length)
  end
end
