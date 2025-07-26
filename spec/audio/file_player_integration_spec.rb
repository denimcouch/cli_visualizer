# frozen_string_literal: true

require "spec_helper"
require "cli_visualizer/audio/file_player"

RSpec.describe CliVisualizer::Audio::FilePlayer, :integration do
  let(:test_audio_dir) { File.join(spec_fixtures_path, "audio") }

  before do
    FileUtils.mkdir_p(test_audio_dir)
    skip_if_no_decoders
  end

  describe "real file playback" do
    context "when audio decoders are available" do
      it "can create file player instances" do
        test_file = create_minimal_wav_file

        player = described_class.new(file_path: test_file)
        expect(player).to be_a(described_class)
        expect(player.file_path).to eq(test_file)

        cleanup_test_file(test_file)
      end

      it "integrates with capture factory method" do
        test_file = create_minimal_wav_file

        player = CliVisualizer::Audio::Capture.create(
          type: :file,
          file_path: test_file
        )

        expect(player).to be_a(described_class)
        expect(player.file_path).to eq(test_file)

        cleanup_test_file(test_file)
      end

      it "detects available system decoders" do
        decoders = described_class.available_decoders
        expect(decoders).to be_an(Array)

        # At least one decoder should be available for integration tests
        expect(decoders).to include(:ffmpeg).or include(:sox) unless decoders.empty?
      end
    end

    context "with real audio files", :requires_audio_files do
      # These tests require actual audio files to be present
      # Skip if no real audio files are available for testing

      let(:sample_files) do
        Dir.glob(File.join(test_audio_dir, "*.{wav,mp3,flac}")).select do |file|
          File.size(file) > 100 # Ensure files are not empty
        end
      end

      before do
        skip("No real audio files available for testing") if sample_files.empty?
      end

      it "can start and stop playback with real files" do
        sample_files.first(3).each do |file|
          player = described_class.new(file_path: file)

          # Should be able to start
          expect(player.start).to be true
          expect(player.running?).to be true

          # Let it run briefly
          sleep(0.1)

          # Should be able to stop
          expect(player.stop).to be true
          expect(player.stopped?).to be true
        end
      end

      it "detects duration for real audio files" do
        sample_files.first(3).each do |file|
          player = described_class.new(file_path: file)

          # Duration detection depends on available tools
          duration = player.duration_seconds
          if duration
            expect(duration).to be > 0
            expect(duration).to be_a(Float)
          end
        end
      end
    end
  end

  describe "error handling with real system" do
    it "handles missing decoder gracefully" do
      # Temporarily mock system to return no decoders
      allow(described_class).to receive(:available_decoders).and_return([])

      test_file = create_minimal_wav_file

      expect do
        described_class.new(file_path: test_file)
      end.to raise_error(RuntimeError, /No audio decoders found/)

      cleanup_test_file(test_file)
    end

    it "validates file existence in real filesystem" do
      nonexistent_file = File.join(test_audio_dir, "nonexistent.mp3")

      expect do
        described_class.new(file_path: nonexistent_file)
      end.to raise_error(ArgumentError, /File does not exist/)
    end

    it "validates file format in real filesystem" do
      text_file = File.join(test_audio_dir, "not_audio.txt")
      File.write(text_file, "This is not audio data")

      expect do
        described_class.new(file_path: text_file)
      end.to raise_error(ArgumentError, /Unsupported format/)

      cleanup_test_file(text_file)
    end
  end

  describe "callback integration" do
    it "provides audio data through callback system" do
      test_file = create_minimal_wav_file
      player = described_class.new(file_path: test_file)

      received_data = []
      player.on_audio_data { |data| received_data << data }

      # Mock the decoding to provide test data
      allow(player).to receive(:decode_and_stream) do
        # Simulate providing audio data
        test_samples = [0.1, -0.1, 0.2, -0.2]
        player.send(:notify_audio_data, test_samples)
      end

      player.start
      sleep(0.01)
      player.stop

      expect(received_data).not_to be_empty
      expect(received_data.first).to be_an(Array)

      cleanup_test_file(test_file)
    end
  end

  private

  def spec_fixtures_path
    File.join(File.dirname(__FILE__), "..", "fixtures")
  end

  def skip_if_no_decoders
    available = described_class.available_decoders
    skip("No audio decoders (ffmpeg/sox) available on system") if available.empty?
  end

  def create_minimal_wav_file
    # Create a minimal valid WAV file for testing
    wav_file = File.join(test_audio_dir, "test_#{Time.now.to_i}.wav")

    # WAV header for a minimal 1-second 44.1kHz stereo file
    File.open(wav_file, "wb") do |f|
      sample_rate = 44_100
      channels = 2
      bits_per_sample = 16
      samples = sample_rate # 1 second of audio

      # WAV header
      f.write("RIFF")
      f.write([36 + samples * channels * (bits_per_sample / 8)].pack("L<"))
      f.write("WAVE")
      f.write("fmt ")
      f.write([16].pack("L<")) # fmt chunk size
      f.write([1].pack("S<"))  # audio format (PCM)
      f.write([channels].pack("S<"))
      f.write([sample_rate].pack("L<"))
      f.write([sample_rate * channels * (bits_per_sample / 8)].pack("L<")) # byte rate
      f.write([channels * (bits_per_sample / 8)].pack("S<")) # block align
      f.write([bits_per_sample].pack("S<"))
      f.write("data")
      f.write([samples * channels * (bits_per_sample / 8)].pack("L<"))

      # Generate simple sine wave data
      samples.times do |i|
        # Simple sine wave at 440Hz
        value = (Math.sin(2 * Math::PI * 440 * i / sample_rate) * 16_384).to_i
        f.write([value, value].pack("s<s<")) # stereo
      end
    end

    wav_file
  end

  def cleanup_test_file(file_path)
    File.delete(file_path) if File.exist?(file_path)
  end
end
