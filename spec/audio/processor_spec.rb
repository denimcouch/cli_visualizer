# frozen_string_literal: true

require "spec_helper"
require "cli_visualizer/audio/processor"

RSpec.describe CliVisualizer::Audio::Processor do
  let(:sample_rate) { 44_100 }
  let(:fft_size) { 1024 }
  let(:processor) { described_class.new(sample_rate: sample_rate, fft_size: fft_size) }

  describe "#initialize" do
    it "creates processor with default parameters" do
      default_processor = described_class.new
      expect(default_processor.sample_rate).to eq(44_100)
      expect(default_processor.fft_size).to eq(1024)
      expect(default_processor.overlap).to eq(0.5)
      expect(default_processor.window_type).to eq(:hanning)
    end

    it "creates processor with custom parameters" do
      custom_processor = described_class.new(
        sample_rate: 48_000,
        fft_size: 512,
        overlap: 0.75,
        window: :hamming
      )

      expect(custom_processor.sample_rate).to eq(48_000)
      expect(custom_processor.fft_size).to eq(512)
      expect(custom_processor.overlap).to eq(0.75)
      expect(custom_processor.window_type).to eq(:hamming)
    end

    it "validates FFT size" do
      expect do
        described_class.new(fft_size: 1000) # Not a power of 2
      end.to raise_error(ArgumentError, /FFT size must be one of/)
    end

    it "validates window type" do
      expect do
        described_class.new(window: :invalid)
      end.to raise_error(ArgumentError, /Window type must be one of/)
    end

    it "validates overlap" do
      expect do
        described_class.new(overlap: 1.5) # > 1.0
      end.to raise_error(ArgumentError, /Overlap must be between/)

      expect do
        described_class.new(overlap: -0.1) # < 0.0
      end.to raise_error(ArgumentError, /Overlap must be between/)
    end

    it "validates sample rate" do
      expect do
        described_class.new(sample_rate: -1000)
      end.to raise_error(ArgumentError, /Sample rate must be positive/)
    end
  end

  describe "#frequency_bins" do
    it "generates correct frequency bins" do
      bins = processor.frequency_bins
      expect(bins.length).to eq(fft_size / 2 + 1)
      expect(bins.first).to eq(0.0)
      expect(bins.last).to be_within(0.1).of(sample_rate / 2.0)
    end
  end

  describe "#frequency_to_bin and #bin_to_frequency" do
    it "converts between frequency and bin correctly" do
      frequency = 440.0 # A4 note
      bin = processor.frequency_to_bin(frequency)
      converted_back = processor.bin_to_frequency(bin)

      expect(converted_back).to be_within(10.0).of(frequency)
    end
  end

  describe "#frequency_range" do
    it "returns correct frequency range" do
      range = processor.frequency_range
      expect(range).to eq([0, sample_rate / 2.0])
    end
  end

  describe "#magnitude_bins_count" do
    it "returns correct magnitude bins count" do
      expect(processor.magnitude_bins_count).to eq(fft_size / 2 + 1)
    end
  end

  describe "window functions" do
    let(:window_size) { 128 }

    context "Hanning window" do
      let(:processor) { described_class.new(fft_size: window_size, window: :hanning) }

      it "generates symmetric window" do
        window = processor.send(:generate_window, window_size, :hanning)
        expect(window.length).to eq(window_size)
        expect(window.first).to be_within(0.001).of(0.0)
        expect(window.last).to be_within(0.001).of(0.0)
        expect(window[window_size / 2]).to be > 0.9 # Peak near center
      end
    end

    context "Hamming window" do
      let(:processor) { described_class.new(fft_size: window_size, window: :hamming) }

      it "generates correct Hamming coefficients" do
        window = processor.send(:generate_window, window_size, :hamming)
        expect(window.length).to eq(window_size)
        expect(window.first).to be_within(0.001).of(0.08) # Hamming starts/ends at 0.08
        expect(window.last).to be_within(0.001).of(0.08)
      end
    end

    context "Blackman window" do
      let(:processor) { described_class.new(fft_size: window_size, window: :blackman) }

      it "generates correct Blackman coefficients" do
        window = processor.send(:generate_window, window_size, :blackman)
        expect(window.length).to eq(window_size)
        expect(window.first).to be_within(0.001).of(0.0)
        expect(window.last).to be_within(0.001).of(0.0)
      end
    end

    context "Rectangular window" do
      let(:processor) { described_class.new(fft_size: window_size, window: :rectangular) }

      it "generates all ones" do
        window = processor.send(:generate_window, window_size, :rectangular)
        expect(window).to all(eq(1.0))
      end
    end
  end

  describe "FFT implementation" do
    let(:small_processor) { described_class.new(fft_size: 128) }

    it "computes FFT of simple signals correctly" do
      # Test with DC signal (all ones)
      dc_signal = Array.new(128, 1.0)
      result = small_processor.send(:fft, dc_signal)

      expect(result.length).to eq(128)
      expect(result[0][:real]).to be_within(0.001).of(128.0) # DC component
      expect(result[0][:imag]).to be_within(0.001).of(0.0)

      # All other bins should be near zero for DC signal
      (1...128).each do |i|
        expect(result[i][:real]).to be_within(0.001).of(0.0)
        expect(result[i][:imag]).to be_within(0.001).of(0.0)
      end
    end

    it "handles complex exponential correctly" do
      # Test with single frequency sine wave
      # Generate samples of sin(2*pi*k/N) for k=1
      samples = 128.times.map { |n| Math.sin(2 * Math::PI * n / 128) }
      result = small_processor.send(:fft, samples)

      expect(result.length).to eq(128)

      # For a sine wave at bin 1, we expect peak at bin 1 and bin 127 (complex conjugate)
      expect(result[1][:imag].abs).to be > 50.0 # Significant imaginary component
      expect(result[127][:imag].abs).to be > 50.0
    end

    it "validates input size is power of 2" do
      expect do
        small_processor.send(:fft, [1, 2, 3]) # Size 3, not power of 2
      end.to raise_error(ArgumentError, /FFT size must be a power of 2/)
    end
  end

  describe "audio processing pipeline" do
    let(:received_data) { [] }

    before do
      processor.on_frequency_data { |data| received_data << data }
    end

    it "processes audio samples and generates frequency data" do
      # Generate test signal: 440 Hz sine wave
      frequency = 440.0
      samples_count = fft_size * 2 # Enough for two windows
      samples = samples_count.times.map do |n|
        Math.sin(2 * Math::PI * frequency * n / sample_rate)
      end

      processor.process_samples(samples)

      expect(received_data).not_to be_empty

      frequency_data = received_data.first
      expect(frequency_data).to have_key(:frequencies)
      expect(frequency_data).to have_key(:magnitudes)
      expect(frequency_data).to have_key(:phases)
      expect(frequency_data).to have_key(:sample_rate)
      expect(frequency_data).to have_key(:fft_size)

      expect(frequency_data[:frequencies].length).to eq(fft_size / 2 + 1)
      expect(frequency_data[:magnitudes].length).to eq(fft_size / 2 + 1)
      expect(frequency_data[:phases].length).to eq(fft_size / 2 + 1)
    end

    it "detects correct frequency peaks" do
      # Generate test signal: 1000 Hz sine wave
      test_frequency = 1000.0
      samples = fft_size.times.map do |n|
        Math.sin(2 * Math::PI * test_frequency * n / sample_rate)
      end

      processor.process_samples(samples)

      frequency_data = received_data.first
      magnitudes = frequency_data[:magnitudes]
      frequencies = frequency_data[:frequencies]

      # Find peak frequency
      max_magnitude_index = magnitudes.each_with_index.max[1]
      peak_frequency = frequencies[max_magnitude_index]

      # Should be close to our test frequency
      expect(peak_frequency).to be_within(50).of(test_frequency)
    end

    it "handles overlapping windows correctly" do
      # Test with overlap processing
      overlap_processor = described_class.new(
        sample_rate: sample_rate,
        fft_size: 512,
        overlap: 0.5
      )

      overlap_received = []
      overlap_processor.on_frequency_data { |data| overlap_received << data }

      # Send enough samples for multiple overlapping windows
      samples = Array.new(1024, 0.5)
      overlap_processor.process_samples(samples)

      # Should receive multiple frequency analysis results due to overlap
      expect(overlap_received.length).to be > 1
    end

    it "ignores empty sample arrays" do
      processor.process_samples([])
      expect(received_data).to be_empty
    end
  end

  describe "callback management" do
    it "registers and calls frequency data callbacks" do
      callback_called = false
      callback_data = nil

      processor.on_frequency_data do |data|
        callback_called = true
        callback_data = data
      end

      # Process enough samples to trigger callback
      samples = Array.new(fft_size, 0.1)
      processor.process_samples(samples)

      expect(callback_called).to be true
      expect(callback_data).not_to be_nil
    end

    it "supports multiple callbacks" do
      callback1_called = false
      callback2_called = false

      processor.on_frequency_data { |_| callback1_called = true }
      processor.on_frequency_data { |_| callback2_called = true }

      samples = Array.new(fft_size, 0.1)
      processor.process_samples(samples)

      expect(callback1_called).to be true
      expect(callback2_called).to be true
    end

    it "clears callbacks" do
      callback_called = false
      processor.on_frequency_data { |_| callback_called = true }

      processor.clear_callbacks

      samples = Array.new(fft_size, 0.1)
      processor.process_samples(samples)

      expect(callback_called).to be false
    end

    it "handles callback errors gracefully" do
      processor.on_frequency_data { |_| raise StandardError, "Callback error" }

      # Should not raise error
      expect do
        samples = Array.new(fft_size, 0.1)
        processor.process_samples(samples)
      end.not_to raise_error
    end
  end

  describe "performance characteristics" do
    it "processes large amounts of audio efficiently" do
      large_processor = described_class.new(fft_size: 2048)
      received_count = 0
      large_processor.on_frequency_data { |_| received_count += 1 }

      # Process 10 seconds worth of audio
      total_samples = sample_rate * 10
      batch_size = 4096

      start_time = Time.now

      (total_samples / batch_size).times do
        samples = Array.new(batch_size) { rand(-1.0..1.0) }
        large_processor.process_samples(samples)
      end

      processing_time = Time.now - start_time

      # Should complete in reasonable time (less than 10 seconds for 10 seconds of audio)
      expect(processing_time).to be < 10.0
      expect(received_count).to be > 0
    end
  end

  describe "edge cases" do
    it "handles very quiet signals" do
      quiet_samples = Array.new(fft_size, 0.0001)
      received = []
      processor.on_frequency_data { |data| received << data }

      processor.process_samples(quiet_samples)

      expect(received).not_to be_empty
      expect(received.first[:magnitudes]).to all(be >= 0)
    end

    it "handles loud signals without clipping" do
      loud_samples = Array.new(fft_size, 0.99)
      received = []
      processor.on_frequency_data { |data| received << data }

      processor.process_samples(loud_samples)

      expect(received).not_to be_empty
      expect(received.first[:magnitudes]).to all(be_finite)
    end
  end
end
