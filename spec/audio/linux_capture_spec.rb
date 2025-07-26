# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
RSpec.describe CliVisualizer::Audio::LinuxCapture do
  let(:capture) { described_class.new }

  describe "initialization" do
    it "inherits from Capture base class" do
      expect(capture).to be_a(CliVisualizer::Audio::Capture)
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

    it "detects audio system on initialization" do
      audio_system = capture.instance_variable_get(:@audio_system)
      expect([nil, :pulseaudio, :alsa]).to include(audio_system)
    end
  end

  describe "audio system detection" do
    it "prefers PulseAudio over ALSA" do
      allow(capture).to receive(:pulseaudio_available?).and_return(true)
      allow(capture).to receive(:alsa_available?).and_return(true)

      capture.send(:detect_audio_system)

      expect(capture.instance_variable_get(:@audio_system)).to eq(:pulseaudio)
    end

    it "falls back to ALSA when PulseAudio is unavailable" do
      allow(capture).to receive(:pulseaudio_available?).and_return(false)
      allow(capture).to receive(:alsa_available?).and_return(true)

      capture.send(:detect_audio_system)

      expect(capture.instance_variable_get(:@audio_system)).to eq(:alsa)
    end

    it "sets system to nil when neither is available" do
      allow(capture).to receive(:pulseaudio_available?).and_return(false)
      allow(capture).to receive(:alsa_available?).and_return(false)

      capture.send(:detect_audio_system)

      expect(capture.instance_variable_get(:@audio_system)).to be_nil
    end
  end

  describe "PulseAudio constants" do
    it "defines correct sample format constants" do
      expect(described_class::PA_SAMPLE_U8).to eq(0)
      expect(described_class::PA_SAMPLE_S16LE).to eq(3)
      expect(described_class::PA_SAMPLE_S24LE).to eq(9)
      expect(described_class::PA_SAMPLE_S32LE).to eq(7)
    end

    it "defines correct stream direction constants" do
      expect(described_class::PA_STREAM_RECORD).to eq(2)
      expect(described_class::PA_STREAM_PLAYBACK).to eq(1)
    end
  end

  describe "ALSA constants" do
    it "defines correct stream constants" do
      expect(described_class::SND_PCM_STREAM_CAPTURE).to eq(1)
      expect(described_class::SND_PCM_STREAM_PLAYBACK).to eq(0)
    end

    it "defines correct format constants" do
      expect(described_class::SND_PCM_FORMAT_S16_LE).to eq(2)
      expect(described_class::SND_PCM_FORMAT_S24_LE).to eq(6)
      expect(described_class::SND_PCM_FORMAT_S32_LE).to eq(10)
    end

    it "defines correct access constant" do
      expect(described_class::SND_PCM_ACCESS_RW_INTERLEAVED).to eq(3)
    end
  end

  describe "device information" do
    context "with PulseAudio" do
      before do
        capture.instance_variable_set(:@audio_system, :pulseaudio)
      end

      it "provides PulseAudio-specific device info" do
        info = capture.device_info

        expect(info[:name]).to eq("Linux Pulseaudio Audio")
        expect(info[:sample_rate]).to eq(44_100)
        expect(info[:channels]).to eq(2)
        expect(info[:sample_size]).to eq(16)
        expect(info[:platform]).to eq("Linux")
        expect(info[:audio_system]).to eq(:pulseaudio)
        expect(info[:framework]).to eq("PulseAudio")
      end
    end

    context "with ALSA" do
      before do
        capture.instance_variable_set(:@audio_system, :alsa)
      end

      it "provides ALSA-specific device info" do
        info = capture.device_info

        expect(info[:name]).to eq("Linux Alsa Audio")
        expect(info[:platform]).to eq("Linux")
        expect(info[:audio_system]).to eq(:alsa)
        expect(info[:framework]).to eq("ALSA")
      end
    end

    context "with unknown audio system" do
      before do
        capture.instance_variable_set(:@audio_system, nil)
      end

      it "provides generic device info" do
        info = capture.device_info

        expect(info[:name]).to eq("Linux Unknown Audio")
        expect(info[:audio_system]).to be_nil
      end
    end

    it "reflects custom configuration in device info" do
      custom_capture = described_class.new(sample_rate: 48_000, channels: 1)
      info = custom_capture.device_info

      expect(info[:sample_rate]).to eq(48_000)
      expect(info[:channels]).to eq(1)
    end
  end

  describe ".available_devices" do
    it "returns both PulseAudio and ALSA devices" do
      devices = described_class.available_devices

      expect(devices).to be_an(Array)
      expect(devices.length).to eq(2)

      pulse_device = devices.find { |d| d[:audio_system] == :pulseaudio }
      alsa_device = devices.find { |d| d[:audio_system] == :alsa }

      expect(pulse_device[:id]).to eq("default_pulse")
      expect(pulse_device[:name]).to eq("PulseAudio Default")
      expect(pulse_device[:type]).to eq("input")

      expect(alsa_device[:id]).to eq("default_alsa")
      expect(alsa_device[:name]).to eq("ALSA Default")
      expect(alsa_device[:type]).to eq("input")
    end
  end

  describe "pause and resume" do
    it "implements pause as stop" do
      allow(capture).to receive(:stop).and_return(true)

      result = capture.pause

      expect(capture).to have_received(:stop)
      expect(result).to be true
    end

    it "implements resume as start" do
      allow(capture).to receive(:start).and_return(true)

      result = capture.resume

      expect(capture).to have_received(:start)
      expect(result).to be true
    end
  end

  describe "error handling" do
    it "handles missing audio system gracefully" do
      capture.instance_variable_set(:@audio_system, nil)

      expect { capture.start }.not_to raise_error
      expect(capture.error?).to be true
      expect(capture.error_message).to include("No supported audio system available")
    end

    it "handles PulseAudio initialization errors" do
      capture.instance_variable_set(:@audio_system, :pulseaudio)
      allow(capture).to receive(:start_pulseaudio).and_raise(CliVisualizer::AudioError, "PulseAudio init failed")

      expect { capture.start }.not_to raise_error
      expect(capture.error?).to be true
      expect(capture.error_message).to include("Failed to start Linux audio capture")
    end

    it "handles ALSA initialization errors" do
      capture.instance_variable_set(:@audio_system, :alsa)
      allow(capture).to receive(:start_alsa).and_raise(CliVisualizer::AudioError, "ALSA init failed")

      expect { capture.start }.not_to raise_error
      expect(capture.error?).to be true
      expect(capture.error_message).to include("Failed to start Linux audio capture")
    end

    it "cleans up properly on start failure" do
      capture.instance_variable_set(:@audio_system, :pulseaudio)
      allow(capture).to receive(:start_pulseaudio).and_raise(StandardError, "Test error")
      expect(capture).to receive(:cleanup_audio)

      capture.start

      expect(capture.error?).to be true
      expect(capture.error_message).to include("Failed to start Linux audio capture")
    end
  end

  describe "audio data processing" do
    describe "#buffer_to_audio_data" do
      let(:buffer) { FFI::MemoryPointer.new(:uint8, 1024) }

      context "with 8-bit samples" do
        before do
          capture.instance_variable_set(:@sample_size, 8)
        end

        it "converts 8-bit unsigned to 16-bit signed" do
          # Set some test data: 128 (middle), 0 (min), 255 (max)
          buffer.put_uint8(0, 128)
          buffer.put_uint8(1, 0)
          buffer.put_uint8(2, 255)

          audio_data = capture.send(:buffer_to_audio_data, buffer, 3)

          expect(audio_data[0]).to eq(0) # 128 - 128 = 0, * 256 = 0
          expect(audio_data[1]).to eq(-32_768) # 0 - 128 = -128, * 256 = -32768
          expect(audio_data[2]).to eq(32_512)  # 255 - 128 = 127, * 256 = 32512
        end
      end

      context "with 16-bit samples" do
        before do
          capture.instance_variable_set(:@sample_size, 16)
        end

        it "reads 16-bit samples directly" do
          buffer.put_int16(0, 1000)
          buffer.put_int16(2, -500)

          audio_data = capture.send(:buffer_to_audio_data, buffer, 2)

          expect(audio_data[0]).to eq(1000)
          expect(audio_data[1]).to eq(-500)
        end
      end

      context "with 24-bit samples" do
        before do
          capture.instance_variable_set(:@sample_size, 24)
        end

        it "converts 24-bit to 16-bit" do
          # Write a 24-bit sample: 0x123456 (little-endian: 56 34 12)
          buffer.put_uint8(0, 0x56)
          buffer.put_uint8(1, 0x34)
          buffer.put_uint8(2, 0x12)

          audio_data = capture.send(:buffer_to_audio_data, buffer, 1)

          # 0x123456 >> 8 = 0x1234 = 4660
          expect(audio_data[0]).to eq(4660)
        end

        it "handles negative 24-bit samples" do
          # Write a negative 24-bit sample: 0x876543 (little-endian: 43 65 87)
          buffer.put_uint8(0, 0x43)
          buffer.put_uint8(1, 0x65)
          buffer.put_uint8(2, 0x87)

          audio_data = capture.send(:buffer_to_audio_data, buffer, 1)

          # 0x876543 - 0x800000 = 0x076543, >> 8 = 0x765 = 1893
          expected = (0x876543 - 0x800000) >> 8
          expect(audio_data[0]).to eq(expected)
        end
      end

      context "with 32-bit samples" do
        before do
          capture.instance_variable_set(:@sample_size, 32)
        end

        it "converts 32-bit to 16-bit" do
          buffer.put_int32(0, 0x12345678)
          buffer.put_int32(4, -0x12345678)

          audio_data = capture.send(:buffer_to_audio_data, buffer, 2)

          expect(audio_data[0]).to eq(0x1234) # 0x12345678 >> 16
          expect(audio_data[1]).to eq(-4661) # -0x12345678 >> 16 = -4661 in Ruby
        end
      end

      context "with unknown sample size" do
        before do
          capture.instance_variable_set(:@sample_size, 12) # Unsupported size
        end

        it "falls back to 16-bit processing" do
          buffer.put_int16(0, 2000)

          audio_data = capture.send(:buffer_to_audio_data, buffer, 1)

          expect(audio_data[0]).to eq(2000)
        end
      end
    end
  end

  describe "resource management" do
    it "initializes with clean state" do
      expect(capture.instance_variable_get(:@pa_simple)).to be_nil
      expect(capture.instance_variable_get(:@alsa_pcm)).to be_nil
      expect(capture.instance_variable_get(:@capture_thread)).to be_nil
      expect(capture.instance_variable_get(:@running)).to be false
    end

    describe "#cleanup_audio" do
      it "cleans up PulseAudio resources safely" do
        mock_pa_simple = FFI::MemoryPointer.new(:pointer)
        capture.instance_variable_set(:@pa_simple, mock_pa_simple)

        # Mock the cleanup functions if they exist
        allow(described_class).to receive(:pa_simple_free) if described_class.respond_to?(:pa_simple_free)

        # Should not raise errors even if cleanup functions don't exist
        expect { capture.send(:cleanup_audio) }.not_to raise_error

        # In cross-platform test environments, cleanup may or may not clear variables
        # depending on function availability - this is expected behavior
        expect(capture.instance_variable_get(:@pa_simple)).to be_nil
      end

      it "cleans up ALSA resources safely" do
        mock_alsa_pcm = FFI::MemoryPointer.new(:pointer)
        capture.instance_variable_set(:@alsa_pcm, mock_alsa_pcm)

        # Mock the cleanup functions if they exist
        allow(described_class).to receive(:snd_pcm_drop) if described_class.respond_to?(:snd_pcm_drop)
        allow(described_class).to receive(:snd_pcm_close) if described_class.respond_to?(:snd_pcm_close)

        # Should not raise errors even if cleanup functions don't exist
        expect { capture.send(:cleanup_audio) }.not_to raise_error

        expect(capture.instance_variable_get(:@alsa_pcm)).to be_nil
      end

      it "handles cleanup errors gracefully" do
        mock_pa_simple = FFI::MemoryPointer.new(:pointer)
        capture.instance_variable_set(:@pa_simple, mock_pa_simple)

        # Mock cleanup to raise an error
        allow(described_class).to receive(:pa_simple_free).and_raise(StandardError, "Cleanup error")

        # Should not raise errors - cleanup should be resilient
        expect { capture.send(:cleanup_audio) }.not_to raise_error

        # Should still clear the instance variable
        expect(capture.instance_variable_get(:@pa_simple)).to be_nil
      end
    end
  end

  describe "stop functionality" do
    before do
      capture.instance_variable_set(:@running, true)
      capture.instance_variable_set(:@status, CliVisualizer::Audio::Capture::STATUS_RUNNING)
    end

    it "stops capture thread and cleans up resources" do
      mock_thread = instance_double(Thread)
      capture.instance_variable_set(:@capture_thread, mock_thread)

      allow(mock_thread).to receive(:join).with(1.0)
      expect(capture).to receive(:cleanup_audio)

      result = capture.stop

      expect(result).to be true
      expect(capture.stopped?).to be true
      expect(capture.instance_variable_get(:@running)).to be false
    end

    it "handles stop errors gracefully" do
      allow(capture).to receive(:cleanup_audio).and_raise(StandardError, "Stop error")

      expect { capture.stop }.not_to raise_error
      expect(capture.error?).to be true
      expect(capture.error_message).to include("Failed to stop Linux audio capture")
    end

    it "returns true if already stopped" do
      capture.instance_variable_set(:@status, CliVisualizer::Audio::Capture::STATUS_STOPPED)

      result = capture.stop

      expect(result).to be true
    end
  end

  describe "audio system availability checks" do
    describe "#pulseaudio_available?" do
      it "returns false when pa_simple_new method is not available" do
        allow(capture).to receive(:respond_to?).with(:pa_simple_new).and_return(false)

        result = capture.send(:pulseaudio_available?)

        expect(result).to be false
      end

      it "returns false when PulseAudio connection fails" do
        allow(capture).to receive(:respond_to?).with(:pa_simple_new).and_return(true)
        allow(described_class).to receive(:pa_simple_new).and_return(FFI::Pointer::NULL)

        result = capture.send(:pulseaudio_available?)

        expect(result).to be false
      end
    end

    describe "#alsa_available?" do
      it "returns false when snd_pcm_open method is not available" do
        allow(capture).to receive(:respond_to?).with(:snd_pcm_open).and_return(false)

        result = capture.send(:alsa_available?)

        expect(result).to be false
      end

      it "returns false when ALSA device open fails" do
        allow(capture).to receive(:respond_to?).with(:snd_pcm_open).and_return(true)
        allow(described_class).to receive(:snd_pcm_open).and_return(-1)

        result = capture.send(:alsa_available?)

        expect(result).to be false
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
