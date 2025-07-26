# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
RSpec.describe CliVisualizer::Audio::MacOSCapture do
  let(:capture) { described_class.new }

  describe "initialization" do
    it "inherits from Capture base class" do
      expect(capture).to be_a(CliVisualizer::Audio::Capture)
    end

    it "sets up audio format on initialization" do
      expect(capture.instance_variable_get(:@audio_format)).not_to be_nil
    end

    it "initializes with stopped status" do
      expect(capture.stopped?).to be true
      expect(capture.running?).to be false
    end

    it "sets default audio configuration" do
      expect(capture.sample_rate).to eq(44_100)
      expect(capture.channels).to eq(2)
      expect(capture.sample_size).to eq(16)
    end

    it "allows custom audio configuration" do
      custom_capture = described_class.new(sample_rate: 48_000, channels: 1, sample_size: 24)
      expect(custom_capture.sample_rate).to eq(48_000)
      expect(custom_capture.channels).to eq(1)
      expect(custom_capture.sample_size).to eq(24)
    end
  end

  describe "device information" do
    it "provides macOS-specific device info" do
      info = capture.device_info

      expect(info[:name]).to eq("macOS System Audio")
      expect(info[:sample_rate]).to eq(44_100)
      expect(info[:channels]).to eq(2)
      expect(info[:sample_size]).to eq(16)
      expect(info[:platform]).to eq("macOS")
      expect(info[:framework]).to eq("Core Audio")
    end

    it "reflects custom configuration in device info" do
      custom_capture = described_class.new(sample_rate: 48_000, channels: 1)
      info = custom_capture.device_info

      expect(info[:sample_rate]).to eq(48_000)
      expect(info[:channels]).to eq(1)
    end
  end

  describe ".available_devices" do
    it "returns default system audio device" do
      devices = described_class.available_devices

      expect(devices).to be_an(Array)
      expect(devices.length).to eq(1)

      device = devices.first
      expect(device[:id]).to eq("default")
      expect(device[:name]).to eq("System Audio")
      expect(device[:type]).to eq("output")
      expect(device[:sample_rate]).to eq(44_100)
      expect(device[:channels]).to eq(2)
    end
  end

  describe "audio format setup" do
    it "configures AudioStreamBasicDescription correctly" do
      audio_format = capture.instance_variable_get(:@audio_format)

      expect(audio_format[:sample_rate]).to eq(44_100.0)
      expect(audio_format[:format_id]).to eq(described_class::K_AUDIO_FORMAT_LINEAR_PCM)
      expect(audio_format[:format_flags]).to eq(
        described_class::K_AUDIO_FORMAT_FLAG_IS_SIGNED_INTEGER |
        described_class::K_AUDIO_FORMAT_FLAG_IS_PACKED
      )
      expect(audio_format[:channels_per_frame]).to eq(2)
      expect(audio_format[:bits_per_channel]).to eq(16)
      expect(audio_format[:bytes_per_frame]).to eq(4) # 2 channels * 16 bits / 8
      expect(audio_format[:bytes_per_packet]).to eq(4)
      expect(audio_format[:frames_per_packet]).to eq(1)
    end

    it "adapts format to custom configuration" do
      custom_capture = described_class.new(sample_rate: 48_000, channels: 1, sample_size: 24)
      audio_format = custom_capture.instance_variable_get(:@audio_format)

      expect(audio_format[:sample_rate]).to eq(48_000.0)
      expect(audio_format[:channels_per_frame]).to eq(1)
      expect(audio_format[:bits_per_channel]).to eq(24)
      expect(audio_format[:bytes_per_frame]).to eq(3) # 1 channel * 24 bits / 8
      expect(audio_format[:bytes_per_packet]).to eq(3)
    end
  end

  describe "Core Audio constants" do
    it "defines correct Audio Unit constants" do
      expect(described_class::AU_TYPE_OUTPUT).to eq(0x61756f75)
      expect(described_class::AU_SUBTYPE_HAL_OUTPUT).to eq(0x6168616c)
      expect(described_class::AU_MANUFACTURER_APPLE).to eq(0x6170706c)
    end

    it "defines correct property constants" do
      expect(described_class::K_AUDIO_UNIT_PROPERTY_ENABLE_IO).to eq(2003)
      expect(described_class::K_AUDIO_UNIT_PROPERTY_SET_RENDER_CALLBACK).to eq(23)
      expect(described_class::K_AUDIO_UNIT_PROPERTY_STREAM_FORMAT).to eq(8)
    end

    it "defines correct scope constants" do
      expect(described_class::K_AUDIO_UNIT_SCOPE_INPUT).to eq(1)
      expect(described_class::K_AUDIO_UNIT_SCOPE_OUTPUT).to eq(0)
    end

    it "defines correct format constants" do
      expect(described_class::K_AUDIO_FORMAT_LINEAR_PCM).to eq(0x6c70636d)
      expect(described_class::NO_ERR).to eq(0)
    end
  end

  describe "test audio generation" do
    it "generates sine wave test data" do
      frame_count = 1024
      audio_data = capture.send(:generate_test_audio_data, frame_count)

      expect(audio_data).to be_an(Array)
      expect(audio_data.length).to eq(frame_count * 2) # stereo

      # Check that it's actually a sine wave (should have values between -3276 and 3276)
      expect(audio_data.all? { |sample| sample.between?(-4000, 4000) }).to be true

      # Check that it's not all zeros or constant
      expect(audio_data.uniq.length).to be > 10
    end

    it "maintains phase between calls" do
      # Get two consecutive buffers
      audio_data1 = capture.send(:generate_test_audio_data, 100)
      audio_data2 = capture.send(:generate_test_audio_data, 100)

      # The phase should continue from the first call to the second
      # This means the last sample of the first buffer and first sample
      # of the second buffer should form a continuous wave
      expect(audio_data1).not_to eq(audio_data2[0, 200])
    end
  end

  describe "pause and resume" do
    it "implements pause as stop" do
      # Mock the stop method to verify it's called
      allow(capture).to receive(:stop).and_return(true)

      result = capture.pause

      expect(capture).to have_received(:stop)
      expect(result).to be true
    end

    it "implements resume as start" do
      # Mock the start method to verify it's called
      allow(capture).to receive(:start).and_return(true)

      result = capture.resume

      expect(capture).to have_received(:start)
      expect(result).to be true
    end
  end

  describe "error handling" do
    it "handles audio unit setup errors gracefully" do
      # Mock the setup_audio_unit method to raise an AudioError
      allow(capture).to receive(:setup_audio_unit).and_raise(CliVisualizer::AudioError,
                                                             "Could not find HAL output audio component")

      expect { capture.start }.not_to raise_error
      expect(capture.error?).to be true
      expect(capture.error_message).to include("Could not find HAL output audio component")
    end

    it "handles audio unit creation errors" do
      # Mock the setup_audio_unit method to raise an AudioError for instance creation
      allow(capture).to receive(:setup_audio_unit).and_raise(CliVisualizer::AudioError,
                                                             "Failed to create audio unit: 1")

      expect { capture.start }.not_to raise_error
      expect(capture.error?).to be true
      expect(capture.error_message).to include("Failed to create audio unit")
    end

    it "cleans up properly on start failure" do
      # Verify cleanup is called when start fails
      allow(capture).to receive(:setup_audio_unit).and_raise(StandardError, "Test error")
      expect(capture).to receive(:cleanup_audio_unit)

      capture.start

      expect(capture.error?).to be true
      expect(capture.error_message).to include("Failed to start audio capture")
    end
  end

  describe "callback handling" do
    before do
      # Set up the capture in a state where callback can be tested
      capture.instance_variable_set(:@status, described_class::STATUS_RUNNING)
    end

    it "handles audio callback without errors" do
      frame_count = 512

      # Mock the callback parameters
      ref_con = FFI::MemoryPointer.new(:pointer)
      action_flags = FFI::MemoryPointer.new(:pointer)
      time_stamp = FFI::MemoryPointer.new(:pointer)
      data = FFI::MemoryPointer.new(:pointer)

      result = capture.send(:handle_audio_callback, ref_con, action_flags, time_stamp, 0, frame_count, data)

      expect(result).to eq(described_class::NO_ERR)
    end

    it "notifies listeners with audio data" do
      callback_data = nil
      capture.on_audio_data { |data| callback_data = data }

      frame_count = 256
      ref_con = FFI::MemoryPointer.new(:pointer)
      action_flags = FFI::MemoryPointer.new(:pointer)
      time_stamp = FFI::MemoryPointer.new(:pointer)
      data = FFI::MemoryPointer.new(:pointer)

      capture.send(:handle_audio_callback, ref_con, action_flags, time_stamp, 0, frame_count, data)

      expect(callback_data).not_to be_nil
      expect(callback_data).to be_an(Array)
      expect(callback_data.length).to eq(frame_count * 2) # stereo
    end

    it "handles callback errors gracefully" do
      # Mock an error in the callback
      allow(capture).to receive(:generate_test_audio_data).and_raise(StandardError, "Callback test error")

      frame_count = 256
      ref_con = FFI::MemoryPointer.new(:pointer)
      action_flags = FFI::MemoryPointer.new(:pointer)
      time_stamp = FFI::MemoryPointer.new(:pointer)
      data = FFI::MemoryPointer.new(:pointer)

      result = capture.send(:handle_audio_callback, ref_con, action_flags, time_stamp, 0, frame_count, data)

      expect(result).to eq(-1) # Error code
      expect(capture.error?).to be true
      expect(capture.error_message).to include("Audio callback error")
    end

    it "returns immediately when not running" do
      capture.instance_variable_set(:@status, described_class::STATUS_STOPPED)

      ref_con = FFI::MemoryPointer.new(:pointer)
      action_flags = FFI::MemoryPointer.new(:pointer)
      time_stamp = FFI::MemoryPointer.new(:pointer)
      data = FFI::MemoryPointer.new(:pointer)

      result = capture.send(:handle_audio_callback, ref_con, action_flags, time_stamp, 0, 512, data)

      expect(result).to eq(described_class::NO_ERR)
    end
  end
  # rubocop:enable Metrics/BlockLength

  describe "cleanup" do
    it "cleans up audio unit safely when nil" do
      capture.instance_variable_set(:@audio_unit, nil)

      expect { capture.send(:cleanup_audio_unit) }.not_to raise_error
    end

    it "handles cleanup errors gracefully" do
      # Mock an audio unit pointer
      mock_audio_unit = FFI::MemoryPointer.new(:pointer)
      capture.instance_variable_set(:@audio_unit, mock_audio_unit)

      # Mock cleanup functions to raise errors
      allow(described_class).to receive(:AudioUnitUninitialize).and_raise(StandardError, "Cleanup error")
      allow(described_class).to receive(:AudioComponentInstanceDispose).and_raise(StandardError, "Dispose error")

      # Should not raise errors - cleanup should be resilient
      expect { capture.send(:cleanup_audio_unit) }.not_to raise_error

      # Should clear the instance variables
      expect(capture.instance_variable_get(:@audio_unit)).to be_nil
      expect(capture.instance_variable_get(:@buffer_list)).to be_nil
      expect(capture.instance_variable_get(:@render_callback)).to be_nil
    end
  end
end
