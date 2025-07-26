# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
RSpec.describe CliVisualizer::Audio::Capture do
  let(:capture) { described_class.new }

  describe "initialization" do
    it "sets default audio configuration" do
      expect(capture.sample_rate).to eq(44_100)
      expect(capture.channels).to eq(2)
      expect(capture.sample_size).to eq(16)
      expect(capture.buffer_size).to eq(1024)
    end

    it "allows custom audio configuration" do
      custom_capture = described_class.new(
        sample_rate: 48_000,
        channels: 1,
        sample_size: 24,
        buffer_size: 512
      )

      expect(custom_capture.sample_rate).to eq(48_000)
      expect(custom_capture.channels).to eq(1)
      expect(custom_capture.sample_size).to eq(24)
      expect(custom_capture.buffer_size).to eq(512)
    end

    it "starts in stopped status" do
      expect(capture.status).to eq(CliVisualizer::Audio::Capture::STATUS_STOPPED)
      expect(capture.stopped?).to be true
      expect(capture.running?).to be false
      expect(capture.error?).to be false
    end

    it "has no error message initially" do
      expect(capture.error_message).to be_nil
    end
  end

  describe "abstract methods" do
    it "raises NotImplementedError for start" do
      expect { capture.start }.to raise_error(NotImplementedError, /must implement #start/)
    end

    it "raises NotImplementedError for stop" do
      expect { capture.stop }.to raise_error(NotImplementedError, /must implement #stop/)
    end

    it "raises NotImplementedError for pause" do
      expect { capture.pause }.to raise_error(NotImplementedError, /must implement #pause/)
    end

    it "raises NotImplementedError for resume" do
      expect { capture.resume }.to raise_error(NotImplementedError, /must implement #resume/)
    end
  end

  describe "status management" do
    it "provides status query methods" do
      # Test stopped status
      capture.send(:status=, CliVisualizer::Audio::Capture::STATUS_STOPPED)
      expect(capture.stopped?).to be true
      expect(capture.running?).to be false
      expect(capture.error?).to be false

      # Test running status
      capture.send(:status=, CliVisualizer::Audio::Capture::STATUS_RUNNING)
      expect(capture.stopped?).to be false
      expect(capture.running?).to be true
      expect(capture.error?).to be false

      # Test error status
      capture.send(:status=, CliVisualizer::Audio::Capture::STATUS_ERROR)
      expect(capture.stopped?).to be false
      expect(capture.running?).to be false
      expect(capture.error?).to be true
    end

    it "clears error message when setting non-error status" do
      capture.send(:error=, "Test error")
      expect(capture.error_message).to eq("Test error")

      capture.send(:status=, CliVisualizer::Audio::Capture::STATUS_RUNNING)
      expect(capture.error_message).to be_nil
    end

    it "sets error message with error status" do
      capture.send(:error=, "Test error message")
      expect(capture.status).to eq(CliVisualizer::Audio::Capture::STATUS_ERROR)
      expect(capture.error_message).to eq("Test error message")
    end
  end

  describe "callback management" do
    it "allows registering audio data callbacks" do
      callback_called = false
      callback_data = nil

      capture.on_audio_data do |data|
        callback_called = true
        callback_data = data
      end

      test_data = [1, 2, 3, 4, 5]
      capture.send(:notify_audio_data, test_data)

      expect(callback_called).to be true
      expect(callback_data).to eq(test_data)
    end

    it "supports multiple callbacks" do
      callback1_called = false
      callback2_called = false

      capture.on_audio_data { callback1_called = true }
      capture.on_audio_data { callback2_called = true }

      capture.send(:notify_audio_data, [1, 2, 3])

      expect(callback1_called).to be true
      expect(callback2_called).to be true
    end

    it "clears all callbacks" do
      capture.on_audio_data { puts "test" }
      expect(capture.instance_variable_get(:@callbacks)).not_to be_empty

      capture.clear_callbacks
      expect(capture.instance_variable_get(:@callbacks)).to be_empty
    end

    it "handles callback errors gracefully" do
      capture.on_audio_data { raise StandardError, "Callback error" }

      expect { capture.send(:notify_audio_data, [1, 2, 3]) }.not_to raise_error
      expect(capture.error?).to be true
      expect(capture.error_message).to include("Callback error")
    end
  end

  describe "device information" do
    it "provides default device info" do
      info = capture.device_info

      expect(info[:name]).to eq("Unknown Device")
      expect(info[:sample_rate]).to eq(44_100)
      expect(info[:channels]).to eq(2)
      expect(info[:sample_size]).to eq(16)
    end

    it "reflects custom configuration in device info" do
      custom_capture = described_class.new(sample_rate: 48_000, channels: 1)
      info = custom_capture.device_info

      expect(info[:sample_rate]).to eq(48_000)
      expect(info[:channels]).to eq(1)
    end
  end

  describe "class methods" do
    describe ".available_devices" do
      it "returns empty array by default" do
        expect(described_class.available_devices).to eq([])
      end
    end

    describe ".create" do
      it "raises ArgumentError for unknown capture type" do
        expect { described_class.create(type: :unknown) }.to raise_error(ArgumentError, /Unknown capture type/)
      end

      # NOTE: We can't test the actual platform-specific creation here
      # since it would require the platform-specific classes to exist
      # We'll test this integration in higher-level tests once those are implemented
    end
  end
end
# rubocop:enable Metrics/BlockLength
