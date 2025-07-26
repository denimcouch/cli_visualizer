# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
RSpec.describe "Audio Capture Integration" do
  describe CliVisualizer::Audio::Capture do
    describe ".create factory method" do
      context "on macOS platform" do
        before do
          # Mock RUBY_PLATFORM to simulate macOS
          stub_const("RUBY_PLATFORM", "x86_64-darwin20")
        end

        it "creates MacOSCapture instance for system audio" do
          capture = described_class.create(type: :system)

          expect(capture).to be_a(CliVisualizer::Audio::MacOSCapture)
          expect(capture).to be_a(CliVisualizer::Audio::Capture)
        end

        it "passes configuration options to MacOSCapture" do
          capture = described_class.create(
            type: :system,
            sample_rate: 48_000,
            channels: 1,
            sample_size: 24
          )

          expect(capture.sample_rate).to eq(48_000)
          expect(capture.channels).to eq(1)
          expect(capture.sample_size).to eq(24)
        end

        it "creates different instances for multiple calls" do
          capture1 = described_class.create(type: :system)
          capture2 = described_class.create(type: :system)

          expect(capture1).not_to be(capture2)
          expect(capture1).to be_a(CliVisualizer::Audio::MacOSCapture)
          expect(capture2).to be_a(CliVisualizer::Audio::MacOSCapture)
        end
      end

      context "on unsupported platform" do
        before do
          # Mock RUBY_PLATFORM to simulate unsupported platform
          stub_const("RUBY_PLATFORM", "x86_64-mingw32")
        end

        it "raises PlatformError for unsupported platform" do
          expect { described_class.create(type: :system) }.to raise_error(
            CliVisualizer::PlatformError,
            /System audio capture not supported on x86_64-mingw32/
          )
        end
      end

      context "platform detection edge cases" do
        it "recognizes various darwin platforms as macOS" do
          darwin_platforms = %w[
            x86_64-darwin20
            arm64-darwin21
            x86_64-darwin19
            universal-darwin20
          ]

          darwin_platforms.each do |platform|
            stub_const("RUBY_PLATFORM", platform)
            capture = described_class.create(type: :system)
            expect(capture).to be_a(CliVisualizer::Audio::MacOSCapture)
          end
        end
      end
    end
  end

  describe CliVisualizer::Audio::MacOSCapture do
    let(:capture) { described_class.new }

    describe "integration with base class" do
      it "properly implements all abstract methods" do
        expect(capture).to respond_to(:start)
        expect(capture).to respond_to(:stop)
        expect(capture).to respond_to(:pause)
        expect(capture).to respond_to(:resume)
      end

      it "inherits status management from base class" do
        expect(capture.stopped?).to be true
        expect(capture.running?).to be false
        expect(capture.error?).to be false
      end

      it "inherits callback management from base class" do
        callback_called = false
        capture.on_audio_data { callback_called = true }

        # Simulate callback with test data
        test_data = [1, 2, 3, 4, 5]
        capture.send(:notify_audio_data, test_data)

        expect(callback_called).to be true
      end

      it "provides enhanced device information" do
        base_info = CliVisualizer::Audio::Capture.new.device_info
        macos_info = capture.device_info

        # Should have all base properties plus macOS-specific ones
        expect(macos_info[:name]).not_to eq(base_info[:name])
        expect(macos_info[:platform]).to eq("macOS")
        expect(macos_info[:framework]).to eq("Core Audio")
        expect(macos_info).to include(:sample_rate, :channels, :sample_size)
      end
    end

    describe "audio format compatibility" do
      it "handles standard CD quality format" do
        cd_capture = described_class.new(sample_rate: 44_100, channels: 2, sample_size: 16)
        audio_format = cd_capture.instance_variable_get(:@audio_format)

        expect(audio_format[:sample_rate]).to eq(44_100.0)
        expect(audio_format[:channels_per_frame]).to eq(2)
        expect(audio_format[:bits_per_channel]).to eq(16)
      end

      it "handles high-quality audio format" do
        hq_capture = described_class.new(sample_rate: 96_000, channels: 2, sample_size: 24)
        audio_format = hq_capture.instance_variable_get(:@audio_format)

        expect(audio_format[:sample_rate]).to eq(96_000.0)
        expect(audio_format[:channels_per_frame]).to eq(2)
        expect(audio_format[:bits_per_channel]).to eq(24)
      end

      it "handles mono audio format" do
        mono_capture = described_class.new(sample_rate: 44_100, channels: 1, sample_size: 16)
        audio_format = mono_capture.instance_variable_get(:@audio_format)

        expect(audio_format[:channels_per_frame]).to eq(1)
        expect(audio_format[:bytes_per_frame]).to eq(2) # 1 channel * 16 bits / 8
      end
    end

    describe "callback integration" do
      it "integrates callbacks with audio data generation" do
        received_data = []
        capture.on_audio_data { |data| received_data.concat(data) }

        # Set capture to running state for callback processing
        capture.instance_variable_set(:@status, CliVisualizer::Audio::Capture::STATUS_RUNNING)

        # Simulate multiple callback invocations
        ref_con = FFI::MemoryPointer.new(:pointer)
        action_flags = FFI::MemoryPointer.new(:pointer)
        time_stamp = FFI::MemoryPointer.new(:pointer)
        data = FFI::MemoryPointer.new(:pointer)

        # Process multiple buffers
        3.times do
          capture.send(:handle_audio_callback, ref_con, action_flags, time_stamp, 0, 256, data)
        end

        # Should have received audio data from all callbacks
        expect(received_data.length).to eq(256 * 2 * 3) # 256 frames * 2 channels * 3 calls
        expect(received_data.all? { |sample| sample.is_a?(Integer) }).to be true
      end

      it "handles multiple simultaneous listeners" do
        listener1_data = []
        listener2_data = []

        capture.on_audio_data { |data| listener1_data.concat(data) }
        capture.on_audio_data { |data| listener2_data.concat(data) }

        capture.instance_variable_set(:@status, CliVisualizer::Audio::Capture::STATUS_RUNNING)

        ref_con = FFI::MemoryPointer.new(:pointer)
        action_flags = FFI::MemoryPointer.new(:pointer)
        time_stamp = FFI::MemoryPointer.new(:pointer)
        data = FFI::MemoryPointer.new(:pointer)

        capture.send(:handle_audio_callback, ref_con, action_flags, time_stamp, 0, 128, data)

        # Both listeners should receive the same data
        expect(listener1_data).to eq(listener2_data)
        expect(listener1_data.length).to eq(128 * 2) # 128 frames * 2 channels
      end
    end

    describe "resource management" do
      it "initializes with clean state" do
        expect(capture.instance_variable_get(:@audio_unit)).to be_nil
        expect(capture.instance_variable_get(:@capture_thread)).to be_nil
        expect(capture.instance_variable_get(:@render_callback)).to be_nil
        expect(capture.instance_variable_get(:@buffer_list)).to be_nil
      end

      it "clears all resources on cleanup" do
        # Set up some mock state
        capture.instance_variable_set(:@audio_unit, FFI::MemoryPointer.new(:pointer))
        capture.instance_variable_set(:@buffer_list, CliVisualizer::Audio::MacOSCapture::AudioBufferList.new)
        capture.instance_variable_set(:@render_callback, -> {})

        # Mock the cleanup functions to avoid actual Core Audio calls
        allow(CliVisualizer::Audio::MacOSCapture).to receive(:AudioUnitUninitialize)
        allow(CliVisualizer::Audio::MacOSCapture).to receive(:AudioComponentInstanceDispose)

        capture.send(:cleanup_audio_unit)

        expect(capture.instance_variable_get(:@audio_unit)).to be_nil
        expect(capture.instance_variable_get(:@buffer_list)).to be_nil
        expect(capture.instance_variable_get(:@render_callback)).to be_nil
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
