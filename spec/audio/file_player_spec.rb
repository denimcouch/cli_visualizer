# frozen_string_literal: true

require "spec_helper"
require "cli_visualizer/audio/file_player"
require "tempfile"

RSpec.describe CliVisualizer::Audio::FilePlayer do
  let(:sample_wav_file) { File.join(spec_fixtures_path, "sample.wav") }
  let(:sample_mp3_file) { File.join(spec_fixtures_path, "sample.mp3") }
  let(:sample_flac_file) { File.join(spec_fixtures_path, "sample.flac") }

  before do
    # Create test fixtures directory if it doesn't exist
    FileUtils.mkdir_p(spec_fixtures_path)

    # Create dummy audio files for testing
    create_test_audio_files
  end

  after do
    # Clean up test files
    cleanup_test_audio_files
  end

  describe ".supported_format?" do
    it "returns true for supported formats" do
      expect(described_class.supported_format?("test.mp3")).to be true
      expect(described_class.supported_format?("test.wav")).to be true
      expect(described_class.supported_format?("test.flac")).to be true
      expect(described_class.supported_format?("test.m4a")).to be true
      expect(described_class.supported_format?("test.aac")).to be true
      expect(described_class.supported_format?("test.ogg")).to be true
    end

    it "returns false for unsupported formats" do
      expect(described_class.supported_format?("test.txt")).to be false
      expect(described_class.supported_format?("test.doc")).to be false
      expect(described_class.supported_format?("test.avi")).to be false
    end

    it "handles case insensitive extensions" do
      expect(described_class.supported_format?("test.MP3")).to be true
      expect(described_class.supported_format?("test.WaV")).to be true
      expect(described_class.supported_format?("test.FLAC")).to be true
    end
  end

  describe ".available_decoders" do
    it "returns available decoders on the system" do
      decoders = described_class.available_decoders
      expect(decoders).to be_an(Array)
      # We can't guarantee what's installed, but it should be an array
    end
  end

  describe "#initialize" do
    context "with valid file" do
      it "creates a file player successfully" do
        player = described_class.new(file_path: sample_wav_file)
        expect(player.file_path).to eq(sample_wav_file)
        expect(player.status).to eq(CliVisualizer::Audio::Capture::STATUS_STOPPED)
      end

      it "accepts custom audio parameters" do
        player = described_class.new(
          file_path: sample_wav_file,
          sample_rate: 22_050,
          channels: 1,
          buffer_size: 512
        )
        expect(player.sample_rate).to eq(22_050)
        expect(player.channels).to eq(1)
        expect(player.buffer_size).to eq(512)
      end
    end

    context "with invalid file" do
      it "raises error for non-existent file" do
        expect do
          described_class.new(file_path: "/nonexistent/file.mp3")
        end.to raise_error(ArgumentError, /File does not exist/)
      end

      it "raises error for unsupported format" do
        unsupported_file = File.join(spec_fixtures_path, "test.txt")
        File.write(unsupported_file, "not audio data")

        expect do
          described_class.new(file_path: unsupported_file)
        end.to raise_error(ArgumentError, /Unsupported format/)

        File.delete(unsupported_file)
      end
    end

    context "when no decoders are available" do
      it "raises error if no audio decoders found" do
        allow(described_class).to receive(:available_decoders).and_return([])

        expect do
          described_class.new(file_path: sample_wav_file)
        end.to raise_error(RuntimeError, /No audio decoders found/)
      end
    end
  end

  describe "#device_info" do
    let(:player) { described_class.new(file_path: sample_wav_file) }

    it "returns comprehensive device information" do
      info = player.device_info

      expect(info[:name]).to include("File Player")
      expect(info[:file_path]).to eq(sample_wav_file)
      expect(info[:format]).to eq(".wav")
      expect(info[:sample_rate]).to eq(44_100)
      expect(info[:channels]).to eq(2)
      expect(info[:sample_size]).to eq(16)
      expect(info).to have_key(:duration)
      expect(info).to have_key(:position)
    end
  end

  describe "playback control" do
    let(:player) { described_class.new(file_path: sample_wav_file) }

    before do
      # Mock system calls to avoid actually running ffmpeg/sox
      allow_system_calls_mocking
    end

    describe "#start" do
      it "starts playback successfully" do
        mock_successful_decode(player)

        expect(player.start).to be true
        expect(player.status).to eq(CliVisualizer::Audio::Capture::STATUS_RUNNING)
      end

      it "returns false if already running" do
        mock_successful_decode(player)
        player.start

        expect(player.start).to be false
      end

      it "handles start errors gracefully" do
        # Mock Thread.new to immediately raise the error instead of starting a thread
        allow(Thread).to receive(:new).and_raise(StandardError.new("Thread creation failed"))

        expect(player.start).to be false
        expect(player.status).to eq(CliVisualizer::Audio::Capture::STATUS_ERROR)
        expect(player.error_message).to include("Failed to start playback")
      end
    end

    describe "#stop" do
      it "stops playback successfully" do
        mock_successful_decode(player)
        player.start

        expect(player.stop).to be true
        expect(player.status).to eq(CliVisualizer::Audio::Capture::STATUS_STOPPED)
        expect(player.position).to eq(0.0)
      end

      it "returns false if already stopped" do
        expect(player.stop).to be false
      end
    end

    describe "#pause and #resume" do
      it "pauses and resumes playback" do
        mock_successful_decode(player)
        player.start

        expect(player.pause).to be true
        expect(player.paused?).to be true

        expect(player.resume).to be true
        expect(player.paused?).to be false
      end

      it "returns false when not running" do
        expect(player.pause).to be false
        expect(player.resume).to be false
      end
    end
  end

  describe "audio data callbacks" do
    let(:player) { described_class.new(file_path: sample_wav_file) }
    let(:received_data) { [] }

    before do
      allow_system_calls_mocking
      player.on_audio_data { |data| received_data << data }
    end

    it "calls registered callbacks with audio data" do
      mock_audio_data_generation(player, [[0.1, 0.2, 0.3, 0.4]])

      player.start
      sleep(0.1) # Allow some processing time
      player.stop

      expect(received_data).not_to be_empty
      expect(received_data.first).to be_an(Array)
      expect(received_data.first).to all(be_a(Float))
    end
  end

  describe "duration detection" do
    let(:player) { described_class.new(file_path: sample_wav_file) }

    before do
      allow_system_calls_mocking
    end

    it "detects duration using ffprobe when available" do
      mock_ffprobe_duration_detection(10.5)

      player = described_class.new(file_path: sample_wav_file)
      expect(player.duration_seconds).to eq(10.5)
    end

    it "detects duration using soxi when ffprobe unavailable" do
      mock_soxi_duration_detection(8.2)

      player = described_class.new(file_path: sample_wav_file)
      expect(player.duration_seconds).to eq(8.2)
    end

    it "handles duration detection failures gracefully" do
      mock_no_duration_detection

      player = described_class.new(file_path: sample_wav_file)
      expect(player.duration_seconds).to be_nil
    end
  end

  describe "position tracking" do
    let(:player) { described_class.new(file_path: sample_wav_file) }

    before do
      allow_system_calls_mocking
    end

    it "tracks playback position" do
      mock_audio_data_generation(player, [[0.1, 0.2]] * 100) # Multiple chunks

      player.start
      sleep(0.1)
      position_during = player.position_seconds
      player.stop

      expect(position_during).to be > 0
      expect(player.position_seconds).to eq(0.0) # Reset after stop
    end
  end

  private

  def spec_fixtures_path
    File.join(File.dirname(__FILE__), "..", "fixtures")
  end

  def create_test_audio_files
    # Create minimal dummy files for testing
    # These won't be valid audio, but sufficient for testing file validation
    File.write(sample_wav_file, "RIFF....WAVE") unless File.exist?(sample_wav_file)
    File.write(sample_mp3_file, "ID3....") unless File.exist?(sample_mp3_file)
    File.write(sample_flac_file, "fLaC....") unless File.exist?(sample_flac_file)
  end

  def cleanup_test_audio_files
    [sample_wav_file, sample_mp3_file, sample_flac_file].each do |file|
      File.delete(file) if File.exist?(file)
    end
  end

  def allow_system_calls_mocking
    # Mock system calls to prevent actual execution of audio tools
    allow_any_instance_of(described_class).to receive(:system).and_return(true)
  end

  def mock_successful_decode(player)
    # Mock the decode_and_stream method to simulate successful decoding
    allow(player).to receive(:decode_and_stream) do
      # Simulate processing loop
      player.instance_variable_set(:@status, CliVisualizer::Audio::Capture::STATUS_RUNNING)
      sleep(0.01) until player.instance_variable_get(:@stop_requested)
    end
  end

  def mock_audio_data_generation(player, sample_chunks)
    allow(player).to receive(:decode_and_stream) do
      player.instance_variable_set(:@status, CliVisualizer::Audio::Capture::STATUS_RUNNING)

      sample_chunks.each do |samples|
        break if player.instance_variable_get(:@stop_requested)
        next if player.instance_variable_get(:@paused)

        # Update position based on samples processed (like the real method does)
        samples_per_channel = samples.length / player.channels
        current_position = player.instance_variable_get(:@position)
        new_position = current_position + (samples_per_channel.to_f / player.sample_rate)
        player.instance_variable_set(:@position, new_position)

        player.send(:notify_audio_data, samples)
        sleep(0.01)
      end
    end
  end

  def mock_ffprobe_duration_detection(duration)
    allow_any_instance_of(described_class).to receive(:system)
      .with("which ffprobe > /dev/null 2>&1").and_return(true)

    allow(Open3).to receive(:capture3)
      .with("ffprobe", "-v", "quiet", "-print_format", "csv=p=0",
            "-show_entries", "format=duration", anything)
      .and_return([duration.to_s, "", double(success?: true)])
  end

  def mock_soxi_duration_detection(duration)
    allow_any_instance_of(described_class).to receive(:system)
      .with("which ffprobe > /dev/null 2>&1").and_return(false)
    allow_any_instance_of(described_class).to receive(:system)
      .with("which soxi > /dev/null 2>&1").and_return(true)

    allow(Open3).to receive(:capture3)
      .with("soxi", "-D", anything)
      .and_return([duration.to_s, "", double(success?: true)])
  end

  def mock_no_duration_detection
    allow_any_instance_of(described_class).to receive(:system).and_return(false)
  end
end
