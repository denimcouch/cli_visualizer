# frozen_string_literal: true

require "spec_helper"
require "cli_visualizer/audio/source_manager"
require "tempfile"

RSpec.describe CliVisualizer::Audio::SourceManager do
  let(:manager) { described_class.new }

  describe "#initialize" do
    it "creates manager with default configuration" do
      expect(manager.current_source_type).to eq(described_class::SOURCE_NONE)
      expect(manager.current_source).to be_nil
      expect(manager.state).to eq(described_class::STATE_STOPPED)
      expect(manager.available_sources).to be_empty
      expect(manager.switch_count).to eq(0)
    end

    it "creates manager with custom buffer manager" do
      custom_buffer_manager = CliVisualizer::Audio::BufferManager.new(sample_rate: 48_000)
      custom_manager = described_class.new(buffer_manager: custom_buffer_manager)

      expect(custom_manager.buffer_manager).to eq(custom_buffer_manager)
      expect(custom_manager.buffer_manager.sample_rate).to eq(48_000)
    end

    it "sets up main audio buffer" do
      buffer_stats = manager.buffer_manager.stats
      expect(buffer_stats[:buffers]).to have_key("main_audio")
    end
  end

  describe "#create_source" do
    it "creates file audio source" do
      temp_file = create_temp_audio_file

      source_id = manager.create_source("test_file", type: :file, file_path: temp_file.path)
      expect(source_id).to eq("test_file")
      expect(manager.available_sources).to have_key("test_file")

      source_info = manager.available_sources["test_file"]
      expect(source_info[:type]).to eq(:file)
      expect(source_info[:source]).to be_a(CliVisualizer::Audio::FilePlayer)

      cleanup_temp_file(temp_file)
    end

    it "tracks source creation statistics" do
      temp_file = create_temp_audio_file
      initial_count = manager.stats[:sources_created]

      manager.create_source("test", type: :file, file_path: temp_file.path)
      expect(manager.stats[:sources_created]).to eq(initial_count + 1)

      cleanup_temp_file(temp_file)
    end

    it "validates source types" do
      expect do
        manager.create_source("invalid", type: :invalid_type)
      end.to raise_error(ArgumentError, /Invalid source type/)
    end

    it "handles source creation errors gracefully" do
      expect do
        manager.create_source("bad_file", type: :file, file_path: "/nonexistent/file.mp3")
      end.to raise_error(CliVisualizer::Audio::SourceError, /Failed to create/)
    end
  end

  describe "#switch_to_source" do
    let(:temp_file1) { create_temp_audio_file }
    let(:temp_file2) { create_temp_audio_file }

    before do
      manager.create_source("file1", type: :file, file_path: temp_file1.path)
      manager.create_source("file2", type: :file, file_path: temp_file2.path)
    end

    after do
      cleanup_temp_file(temp_file1)
      cleanup_temp_file(temp_file2)
    end

    it "switches to a different source successfully" do
      success = manager.switch_to_source("file1")
      expect(success).to be true
      expect(manager.current_source_type).to eq(:file)
      expect(manager.switch_count).to eq(1)

      # Switch to second source
      success = manager.switch_to_source("file2")
      expect(success).to be true
      expect(manager.switch_count).to eq(2)
    end

    it "records switch history" do
      manager.switch_to_source("file1")
      manager.switch_to_source("file2")

      history = manager.switch_history
      expect(history.length).to eq(2)

      expect(history.first[:from]).to eq(described_class::SOURCE_NONE)
      expect(history.first[:to]).to eq(:file)
      expect(history.first[:success]).to be true

      expect(history.last[:from]).to eq(:file)
      expect(history.last[:to]).to eq(:file)
      expect(history.last[:success]).to be true
    end

    it "prevents concurrent switches" do
      # Start a switch
      manager.switch_to_source("file1")

      # Mock switching in progress
      manager.instance_variable_set(:@switching_in_progress, true)

      # Second switch should fail
      success = manager.switch_to_source("file2")
      expect(success).to be false
    end

    it "handles non-existent source gracefully" do
      success = manager.switch_to_source("nonexistent")
      expect(success).to be false
    end

    it "updates statistics on successful switch" do
      initial_successful = manager.stats[:successful_switches]

      manager.switch_to_source("file1")
      expect(manager.stats[:successful_switches]).to eq(initial_successful + 1)
      expect(manager.stats[:last_switch_time]).to be_within(1).of(Time.now)
    end
  end

  describe "source lifecycle management" do
    let(:temp_file) { create_temp_audio_file }

    before do
      manager.create_source("test_source", type: :file, file_path: temp_file.path)
      manager.switch_to_source("test_source")
    end

    after do
      cleanup_temp_file(temp_file)
    end

    it "starts current source" do
      expect(manager.start).to be true
      expect(manager.running?).to be true
      expect(manager.state).to eq(described_class::STATE_RUNNING)
    end

    it "stops current source" do
      manager.start
      expect(manager.stop).to be true
      expect(manager.stopped?).to be true
      expect(manager.state).to eq(described_class::STATE_STOPPED)
    end

    it "pauses and resumes current source" do
      manager.start
      expect(manager.pause).to be true
      expect(manager.resume).to be true
    end

    it "handles operations with no current source" do
      manager.instance_variable_set(:@current_source, nil)

      expect(manager.start).to be false
      expect(manager.pause).to be false
      expect(manager.resume).to be false
    end

    it "prevents operations during switching" do
      manager.instance_variable_set(:@switching_in_progress, true)

      expect(manager.start).to be false
      expect(manager.stop).to be false
    end
  end

  describe "#current_source_info" do
    let(:temp_file) { create_temp_audio_file }

    before do
      manager.create_source("info_test", type: :file, file_path: temp_file.path)
      manager.switch_to_source("info_test")
    end

    after do
      cleanup_temp_file(temp_file)
    end

    it "provides comprehensive current source information" do
      info = manager.current_source_info

      expect(info).to include(
        :id, :type, :status, :device_info, :created_at, :switch_count, :running
      )

      expect(info[:id]).to eq("info_test")
      expect(info[:type]).to eq(:file)
      expect([true, false]).to include(info[:running]) # Source may auto-start during switch
    end

    it "returns nil when no current source" do
      manager.instance_variable_set(:@current_source, nil)
      expect(manager.current_source_info).to be_nil
    end
  end

  describe "#list_sources" do
    let(:temp_file1) { create_temp_audio_file }
    let(:temp_file2) { create_temp_audio_file }

    before do
      manager.create_source("source1", type: :file, file_path: temp_file1.path)
      manager.create_source("source2", type: :file, file_path: temp_file2.path)
    end

    after do
      cleanup_temp_file(temp_file1)
      cleanup_temp_file(temp_file2)
    end

    it "lists all available sources" do
      sources = manager.list_sources

      expect(sources).to have_key("source1")
      expect(sources).to have_key("source2")

      expect(sources["source1"][:type]).to eq(:file)
      expect(sources["source2"][:type]).to eq(:file)
    end
  end

  describe "#remove_source" do
    let(:temp_file) { create_temp_audio_file }

    before do
      manager.create_source("removable", type: :file, file_path: temp_file.path)
    end

    after do
      cleanup_temp_file(temp_file)
    end

    it "removes non-current sources" do
      expect(manager.remove_source("removable")).to be true
      expect(manager.available_sources).not_to have_key("removable")
    end

    it "prevents removal of current source" do
      manager.switch_to_source("removable")
      expect(manager.remove_source("removable")).to be false
      expect(manager.available_sources).to have_key("removable")
    end

    it "handles non-existent source removal" do
      expect(manager.remove_source("nonexistent")).to be false
    end
  end

  describe "audio data routing" do
    let(:temp_file) { create_temp_audio_file }

    before do
      manager.create_source("routing_test", type: :file, file_path: temp_file.path)
      manager.switch_to_source("routing_test")
    end

    after do
      cleanup_temp_file(temp_file)
    end

    it "routes audio data through callback" do
      received_data = []

      manager.on_audio_data do |samples|
        received_data.concat(samples)
      end

      # Simulate audio data from source
      test_samples = [0.1, 0.2, 0.3, 0.4, 0.5]
      manager.buffer_manager.write_to_buffer("main_audio", test_samples)

      expect(received_data).to eq(test_samples)
    end
  end

  describe "quick switching helpers" do
    let(:temp_file) { create_temp_audio_file }

    after do
      cleanup_temp_file(temp_file) if temp_file
    end

    it "switches to system audio with helper method" do
      # Mock successful system source creation
      allow(manager).to receive(:find_or_create_system_source).and_return("system_source")
      allow(manager).to receive(:switch_to_source).with("system_source").and_return(true)

      expect(manager.switch_to_system_audio).to be true
    end

    it "switches to file with helper method" do
      result = manager.switch_to_file(temp_file.path)
      expect(result).to be true
      expect(manager.current_source_type).to eq(:file)
    end

    it "reuses existing file sources" do
      # Create file source twice with same path
      first_switch = manager.switch_to_file(temp_file.path)
      second_switch = manager.switch_to_file(temp_file.path)

      expect(first_switch).to be true
      expect(second_switch).to be true

      # Should only have one source for this file
      file_sources = manager.available_sources.select { |_, info| info[:type] == :file }
      expect(file_sources.size).to eq(1)
    end
  end

  describe "statistics and monitoring" do
    let(:temp_file) { create_temp_audio_file }

    before do
      manager.create_source("stats_test", type: :file, file_path: temp_file.path)
    end

    after do
      cleanup_temp_file(temp_file)
    end

    it "provides comprehensive statistics" do
      stats = manager.stats

      expect(stats).to include(
        :sources_created, :successful_switches, :failed_switches,
        :current_source, :available_source_count, :state, :switch_count,
        :switching_in_progress, :buffer_stats, :uptime, :error_message
      )

      expect(stats[:available_source_count]).to eq(1)
      expect(stats[:state]).to eq(described_class::STATE_STOPPED)
    end

    it "tracks switch history with limits" do
      # Create multiple switches
      5.times do |i|
        temp = create_temp_audio_file
        manager.create_source("source_#{i}", type: :file, file_path: temp.path)
        manager.switch_to_source("source_#{i}")
      end

      # Test limited history
      limited_history = manager.switch_history(limit: 3)
      expect(limited_history.length).to eq(3)

      # Cleanup
      5.times do |i|
        source_info = manager.available_sources["source_#{i}"]
        next unless source_info

        begin
          File.unlink(source_info[:options][:file_path])
        rescue StandardError
          nil
        end
      end
    end

    it "reports health status correctly" do
      expect(manager.healthy?).to be true # No source, no problem

      manager.switch_to_source("stats_test")
      expect(manager.healthy?).to be true # Source exists and buffer is healthy
    end
  end

  describe "error handling" do
    it "handles source creation failures gracefully" do
      expect do
        manager.create_source("bad_source", type: :file, file_path: "/definitely/does/not/exist.wav")
      end.to raise_error(CliVisualizer::Audio::SourceError)
    end

    it "records failed switches in history" do
      initial_failed = manager.stats[:failed_switches]

      # Mock a failed switch
      allow(manager).to receive(:perform_source_switch).and_return(false)
      manager.instance_variable_set(:@error_message, "Test error")

      # Create a source and try to switch
      temp_file = create_temp_audio_file
      manager.create_source("fail_test", type: :file, file_path: temp_file.path)
      manager.switch_to_source("fail_test")

      expect(manager.stats[:failed_switches]).to eq(initial_failed + 1)

      history = manager.switch_history
      failed_switch = history.find { |entry| !entry[:success] }
      expect(failed_switch).not_to be_nil
      expect(failed_switch[:error]).to eq("Test error")

      cleanup_temp_file(temp_file)
    end

    it "handles missing source gracefully in switch" do
      expect(manager.switch_to_source("nonexistent")).to be false
    end
  end

  describe "state management" do
    it "reports correct states" do
      expect(manager.stopped?).to be true
      expect(manager.running?).to be false
      expect(manager.switching?).to be false
      expect(manager.error?).to be false
    end

    it "transitions through switching state" do
      temp_file = create_temp_audio_file
      manager.create_source("state_test", type: :file, file_path: temp_file.path)

      # Mock to slow down switching to observe state
      original_method = manager.method(:perform_source_switch)
      allow(manager).to receive(:perform_source_switch) do |*args|
        expect(manager.state).to eq(described_class::STATE_SWITCHING)
        original_method.call(*args)
      end

      manager.switch_to_source("state_test")
      cleanup_temp_file(temp_file)
    end
  end

  # Helper methods for test setup
  private

  def create_temp_audio_file
    temp_file = Tempfile.new(["test_audio", ".wav"])
    temp_file.write("RIFF#{[44].pack("V")}WAVE") # Minimal WAV header
    temp_file.close
    temp_file
  end

  def cleanup_temp_file(temp_file)
    temp_file.unlink if temp_file
  rescue StandardError
    # Ignore cleanup errors
  end

  def spec_fixtures_path
    File.join(__dir__, "..", "fixtures")
  end
end
