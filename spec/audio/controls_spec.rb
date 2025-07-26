# frozen_string_literal: true

require "spec_helper"
require "cli_visualizer/audio/controls"

RSpec.describe CliVisualizer::Audio::Controls do
  let(:controls) { described_class.new }

  describe "#initialize" do
    it "creates controls with default settings" do
      expect(controls.gain).to eq(1.0)
      expect(controls.sensitivity).to eq(1.0)
      expect(controls.agc_enabled).to be false
      expect(controls.limiter_enabled).to be true
      expect(controls.compressor_enabled).to be false
      expect(controls.noise_gate_enabled).to be false
    end

    it "accepts custom settings" do
      custom_controls = described_class.new(
        gain: 2.0,
        sensitivity: 1.5,
        agc_enabled: true,
        limiter_threshold: 0.8
      )

      expect(custom_controls.gain).to eq(2.0)
      expect(custom_controls.sensitivity).to eq(1.5)
      expect(custom_controls.agc_enabled).to be true
      expect(custom_controls.limiter_threshold).to eq(0.8)
    end

    it "validates input parameters" do
      expect do
        described_class.new(gain: -1.0)
      end.to raise_error(ArgumentError, /Gain must be between/)

      expect do
        described_class.new(sensitivity: 0.05)
      end.to raise_error(ArgumentError, /Sensitivity must be between/)
    end

    it "initializes statistics" do
      stats = controls.statistics
      expect(stats[:processed_samples]).to eq(0)
      expect(stats[:peak_level]).to eq(0.0)
      expect(stats[:rms_level]).to eq(0.0)
    end
  end

  describe "#process_samples" do
    let(:test_samples) { [0.1, 0.2, 0.3, 0.4, 0.5] }

    it "returns original samples when no processing is enabled" do
      disabled_controls = described_class.new(
        gain: 1.0,
        sensitivity: 1.0,
        agc_enabled: false,
        limiter_enabled: false,
        compressor_enabled: false,
        noise_gate_enabled: false
      )

      result = disabled_controls.process_samples(test_samples)
      expect(result).to eq(test_samples)
    end

    it "handles empty sample arrays" do
      result = controls.process_samples([])
      expect(result).to eq([])
    end

    it "applies gain correctly" do
      controls.disable_limiter # Disable limiter to test pure gain
      controls.set_gain(2.0)
      result = controls.process_samples(test_samples)
      expected = test_samples.map { |s| s * 2.0 }
      expect(result).to eq(expected)
    end

    it "applies sensitivity scaling" do
      controls.disable_limiter # Disable limiter to test pure sensitivity
      controls.set_sensitivity(2.0)
      result = controls.process_samples(test_samples)
      expected = test_samples.map { |s| s * 2.0 }
      expect(result).to eq(expected)
    end

    it "updates statistics after processing" do
      controls.process_samples(test_samples)
      stats = controls.statistics

      expect(stats[:processed_samples]).to eq(test_samples.length)
      expect(stats[:peak_level]).to be > 0
      expect(stats[:rms_level]).to be > 0
    end
  end

  describe "gain control" do
    it "sets gain within valid range" do
      controls.set_gain(3.0)
      expect(controls.gain).to eq(3.0)
    end

    it "validates gain limits" do
      expect do
        controls.set_gain(-0.5)
      end.to raise_error(ArgumentError, /Gain must be between/)

      expect do
        controls.set_gain(15.0)
      end.to raise_error(ArgumentError, /Gain must be between/)
    end

    it "triggers gain change callbacks" do
      callback_data = nil
      controls.on_gain_change { |data| callback_data = data }

      controls.set_gain(2.5)

      expect(callback_data).not_to be_nil
      expect(callback_data[:old_gain]).to eq(1.0)
      expect(callback_data[:new_gain]).to eq(2.5)
    end
  end

  describe "sensitivity control" do
    it "sets sensitivity within valid range" do
      controls.set_sensitivity(3.0)
      expect(controls.sensitivity).to eq(3.0)
    end

    it "validates sensitivity limits" do
      expect do
        controls.set_sensitivity(0.05)
      end.to raise_error(ArgumentError, /Sensitivity must be between/)

      expect do
        controls.set_sensitivity(10.0)
      end.to raise_error(ArgumentError, /Sensitivity must be between/)
    end
  end

  describe "Automatic Gain Control (AGC)" do
    let(:agc_controls) { described_class.new(agc_enabled: true) }

    it "enables and disables AGC" do
      controls.enable_agc
      expect(controls.agc_enabled).to be true

      controls.disable_agc
      expect(controls.agc_enabled).to be false
    end

    it "adjusts AGC target" do
      controls.set_agc_target(0.6)
      expect(controls.agc_target).to eq(0.6)
    end

    it "validates AGC target range" do
      expect do
        controls.set_agc_target(1.5)
      end.to raise_error(ArgumentError, /AGC target must be between/)
    end

    it "sets AGC timing parameters" do
      controls.set_agc_timing(attack: 0.05, release: 0.4)
      expect(controls.agc_attack).to eq(0.05)
      expect(controls.agc_release).to eq(0.4)
    end

    it "adjusts gain based on signal level" do
      # Test that AGC responds to loud signals by moving toward reduction
      very_loud_samples = Array.new(100, 0.95) # Much louder than AGC target of 0.7

      # Get initial AGC gain
      initial_gain = agc_controls.current_levels[:agc_gain]

      # Process many chunks to allow AGC to adapt
      50.times { agc_controls.process_samples(very_loud_samples) }

      final_gain = agc_controls.current_levels[:agc_gain]

      # AGC should move toward reducing gain (final gain should be less than initial)
      expect(final_gain).to be < initial_gain
    end

    it "increases gain for quiet signals" do
      # Test that AGC responds to quiet signals by moving toward increase
      very_quiet_samples = Array.new(100, 0.05) # Much quieter than AGC target of 0.7

      # Get initial AGC gain
      initial_gain = agc_controls.current_levels[:agc_gain]

      # Process many chunks to allow AGC to adapt
      50.times { agc_controls.process_samples(very_quiet_samples) }

      final_gain = agc_controls.current_levels[:agc_gain]

      # AGC should move toward increasing gain (final gain should be greater than initial)
      expect(final_gain).to be > initial_gain
    end
  end

  describe "Peak Limiter" do
    let(:limiter_controls) { described_class.new(limiter_enabled: true, limiter_threshold: 0.5) }

    it "enables and disables limiter" do
      controls.enable_limiter
      expect(controls.limiter_enabled).to be true

      controls.disable_limiter
      expect(controls.limiter_enabled).to be false
    end

    it "sets limiter threshold" do
      controls.set_limiter_threshold(0.8)
      expect(controls.limiter_threshold).to eq(0.8)
    end

    it "validates limiter threshold range" do
      expect do
        controls.set_limiter_threshold(1.5)
      end.to raise_error(ArgumentError, /Limiter threshold must be between/)
    end

    it "limits peaks above threshold" do
      # Signal that exceeds limiter threshold
      loud_samples = [0.8, 0.9, 1.0, 0.7]

      result = limiter_controls.process_samples(loud_samples)
      peak = result.map(&:abs).max

      expect(peak).to be <= limiter_controls.limiter_threshold
    end

    it "does not affect signals below threshold" do
      quiet_samples = [0.1, 0.2, 0.3, 0.4]

      result = limiter_controls.process_samples(quiet_samples)

      expect(result).to eq(quiet_samples)
    end
  end

  describe "Compressor" do
    let(:compressor_controls) do
      described_class.new(
        compressor_enabled: true,
        compressor_threshold: 0.5,
        compressor_ratio: 4.0
      )
    end

    it "enables and disables compressor" do
      controls.enable_compressor
      expect(controls.compressor_enabled).to be true

      controls.disable_compressor
      expect(controls.compressor_enabled).to be false
    end

    it "sets compressor settings" do
      controls.set_compressor_settings(ratio: 6.0, threshold: 0.7)
      expect(controls.compressor_ratio).to eq(6.0)
      expect(controls.compressor_threshold).to eq(0.7)
    end

    it "validates compressor parameters" do
      expect do
        controls.set_compressor_settings(ratio: 25.0, threshold: 0.5)
      end.to raise_error(ArgumentError, /Compressor ratio must be between/)
    end

    it "compresses signals above threshold" do
      # Signal that exceeds compressor threshold
      loud_samples = [0.8, 0.9, 0.7, 0.6]

      result = compressor_controls.process_samples(loud_samples)
      result_peak = result.map(&:abs).max
      original_peak = loud_samples.map(&:abs).max

      expect(result_peak).to be < original_peak
    end

    it "does not affect signals below threshold" do
      quiet_samples = [0.1, 0.2, 0.3, 0.4]

      result = compressor_controls.process_samples(quiet_samples)

      expect(result).to eq(quiet_samples)
    end
  end

  describe "Noise Gate" do
    let(:gate_controls) do
      described_class.new(
        noise_gate_enabled: true,
        noise_gate_threshold: 0.05
      )
    end

    it "enables and disables noise gate" do
      controls.enable_noise_gate
      expect(controls.noise_gate_enabled).to be true

      controls.disable_noise_gate
      expect(controls.noise_gate_enabled).to be false
    end

    it "sets noise gate threshold" do
      controls.set_noise_gate_threshold(0.02)
      expect(controls.noise_gate_threshold).to eq(0.02)
    end

    it "validates noise gate threshold range" do
      expect do
        controls.set_noise_gate_threshold(0.5)
      end.to raise_error(ArgumentError, /Noise gate threshold must be between/)
    end

    it "attenuates signals below threshold" do
      # Very quiet signal below gate threshold
      quiet_samples = Array.new(10, 0.01)

      result = gate_controls.process_samples(quiet_samples)
      result_rms = Math.sqrt(result.sum { |s| s * s } / result.length)
      original_rms = Math.sqrt(quiet_samples.sum { |s| s * s } / quiet_samples.length)

      expect(result_rms).to be < original_rms
    end

    it "passes signals above threshold" do
      # Signal above gate threshold
      loud_samples = Array.new(10, 0.1)

      result = gate_controls.process_samples(loud_samples)

      expect(result).to eq(loud_samples)
    end

    it "tracks gate state" do
      # Signal below threshold should close gate
      quiet_samples = Array.new(10, 0.01)
      gate_controls.process_samples(quiet_samples)

      levels = gate_controls.current_levels
      expect(levels[:gate_open]).to be false

      # Signal above threshold should open gate
      loud_samples = Array.new(10, 0.1)
      gate_controls.process_samples(loud_samples)

      levels = gate_controls.current_levels
      expect(levels[:gate_open]).to be true
    end
  end

  describe "presets" do
    it "applies live input preset" do
      controls.apply_preset(:live_input)

      expect(controls.gain).to eq(1.2)
      expect(controls.sensitivity).to eq(1.5)
      expect(controls.agc_enabled).to be true
      expect(controls.limiter_enabled).to be true
      expect(controls.compressor_enabled).to be true
      expect(controls.noise_gate_enabled).to be true
    end

    it "applies music file preset" do
      controls.apply_preset(:music_file)

      expect(controls.gain).to eq(1.0)
      expect(controls.sensitivity).to eq(1.0)
      expect(controls.agc_enabled).to be false
      expect(controls.limiter_enabled).to be true
      expect(controls.compressor_enabled).to be false
      expect(controls.noise_gate_enabled).to be false
    end

    it "applies quiet environment preset" do
      controls.apply_preset(:quiet_environment)

      expect(controls.gain).to eq(2.0)
      expect(controls.sensitivity).to eq(2.0)
      expect(controls.agc_enabled).to be true
    end

    it "applies loud environment preset" do
      controls.apply_preset(:loud_environment)

      expect(controls.gain).to eq(0.7)
      expect(controls.sensitivity).to eq(0.8)
      expect(controls.agc_enabled).to be true
    end

    it "applies disabled preset" do
      controls.apply_preset(:disabled)

      expect(controls.gain).to eq(1.0)
      expect(controls.sensitivity).to eq(1.0)
      expect(controls.agc_enabled).to be false
      expect(controls.limiter_enabled).to be false
      expect(controls.compressor_enabled).to be false
      expect(controls.noise_gate_enabled).to be false
    end

    it "raises error for unknown preset" do
      expect do
        controls.apply_preset(:unknown_preset)
      end.to raise_error(ArgumentError, /Unknown preset/)
    end
  end

  describe "statistics and monitoring" do
    let(:test_samples) { [0.1, 0.5, 0.8, 0.3, 0.2] }

    it "tracks processing statistics" do
      controls.process_samples(test_samples)
      stats = controls.statistics

      expect(stats[:processed_samples]).to eq(test_samples.length)
      expect(stats[:peak_level]).to be > 0
      expect(stats[:rms_level]).to be > 0
    end

    it "provides current levels" do
      controls.process_samples(test_samples)
      levels = controls.current_levels

      expect(levels).to include(:peak, :rms, :agc_gain, :limiter_reduction, :compressor_reduction, :gate_open)
    end

    it "provides detailed statistics" do
      controls.process_samples(test_samples)
      detailed = controls.detailed_statistics

      expect(detailed).to include(:effective_gain, :total_gain_reduction, :current_levels, :settings)
    end

    it "provides current settings" do
      settings = controls.current_settings

      expect(settings).to include(:gain, :sensitivity, :agc, :limiter, :compressor, :noise_gate)
      expect(settings[:agc]).to include(:enabled, :target, :attack, :release)
    end

    it "resets statistics" do
      controls.process_samples(test_samples)
      expect(controls.statistics[:processed_samples]).to be > 0

      controls.reset_statistics
      expect(controls.statistics[:processed_samples]).to eq(0)
    end
  end

  describe "callback system" do
    let(:test_samples) { [0.1, 0.5, 0.8, 0.3, 0.2] }

    it "calls level change callbacks" do
      callback_data = nil
      controls.on_level_change { |data| callback_data = data }

      controls.process_samples(test_samples)

      expect(callback_data).not_to be_nil
      expect(callback_data).to include(:peak, :rms, :timestamp)
    end

    it "calls gain change callbacks" do
      callback_data = nil
      controls.on_gain_change { |data| callback_data = data }

      controls.set_gain(2.0)

      expect(callback_data).not_to be_nil
      expect(callback_data[:old_gain]).to eq(1.0)
      expect(callback_data[:new_gain]).to eq(2.0)
    end

    it "supports multiple callbacks" do
      call_count = 0
      2.times { controls.on_level_change { call_count += 1 } }

      controls.process_samples(test_samples)

      expect(call_count).to eq(2)
    end

    it "clears all callbacks" do
      controls.on_level_change {}
      controls.on_gain_change {}

      expect(controls.instance_variable_get(:@level_callbacks)).not_to be_empty
      expect(controls.instance_variable_get(:@gain_change_callbacks)).not_to be_empty

      controls.clear_callbacks

      expect(controls.instance_variable_get(:@level_callbacks)).to be_empty
      expect(controls.instance_variable_get(:@gain_change_callbacks)).to be_empty
    end

    it "handles callback errors gracefully" do
      controls.on_level_change { raise StandardError, "Callback error" }

      expect do
        controls.process_samples(test_samples)
      end.not_to raise_error
    end
  end

  describe "audio processing chain" do
    let(:chain_controls) do
      described_class.new(
        gain: 2.0,
        sensitivity: 1.5,
        agc_enabled: true,
        limiter_enabled: true,
        compressor_enabled: true,
        noise_gate_enabled: true,
        noise_gate_threshold: 0.01
      )
    end

    it "processes samples through complete chain" do
      test_samples = [0.1, 0.3, 0.5, 0.2]

      result = chain_controls.process_samples(test_samples)

      expect(result).to be_an(Array)
      expect(result.length).to eq(test_samples.length)
      expect(result).not_to eq(test_samples) # Should be modified by processing
    end

    it "maintains processing order" do
      # The processing chain should be: gain -> noise gate -> compressor -> AGC -> limiter -> sensitivity
      # This test verifies that the chain doesn't break with all processors enabled

      test_samples = Array.new(100) { rand(-1.0..1.0) }

      expect do
        chain_controls.process_samples(test_samples)
      end.not_to raise_error
    end
  end

  describe "thread safety" do
    let(:test_samples) { Array.new(100) { rand(-1.0..1.0) } }

    it "handles concurrent processing safely" do
      threads = 5.times.map do
        Thread.new do
          10.times { controls.process_samples(test_samples) }
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end

    it "handles concurrent setting changes safely" do
      processing_thread = Thread.new do
        100.times { controls.process_samples(test_samples) }
      end

      control_thread = Thread.new do
        10.times do |i|
          controls.set_gain(1.0 + i * 0.1)
          controls.set_sensitivity(1.0 + i * 0.1)
          sleep(0.001)
        end
      end

      expect { [processing_thread, control_thread].each(&:join) }.not_to raise_error
    end
  end

  describe "validation" do
    it "validates all parameter ranges during initialization" do
      expect do
        described_class.new(agc_target: 1.5)
      end.to raise_error(ArgumentError, /AGC target must be between/)

      expect do
        described_class.new(compressor_ratio: 25.0)
      end.to raise_error(ArgumentError, /Compressor ratio must be between/)

      expect do
        described_class.new(noise_gate_threshold: 0.5)
      end.to raise_error(ArgumentError, /Noise gate threshold must be between/)
    end

    it "validates runtime parameter changes" do
      expect do
        controls.set_agc_target(1.5)
      end.to raise_error(ArgumentError, /AGC target must be between/)

      expect do
        controls.set_limiter_threshold(1.5)
      end.to raise_error(ArgumentError, /Limiter threshold must be between/)
    end
  end

  describe "real-world usage scenarios" do
    it "handles typical music file processing" do
      controls.apply_preset(:music_file)

      # Simulate typical music file samples
      music_samples = Array.new(1000) do |i|
        # Sine wave with some dynamics
        amplitude = 0.3 + 0.4 * Math.sin(i / 100.0)
        amplitude * Math.sin(2 * Math::PI * i / 44.1)
      end

      result = controls.process_samples(music_samples)

      expect(result.length).to eq(music_samples.length)
      expect(result.map(&:abs).max).to be <= 1.0 # Should not clip
    end

    it "handles live microphone input simulation" do
      controls.apply_preset(:live_input)

      # Simulate variable microphone input with noise
      mic_samples = Array.new(1000) do |i|
        # Variable signal with background noise
        signal = 0.1 * Math.sin(2 * Math::PI * i / 100.0)
        noise = 0.01 * (rand - 0.5)
        signal + noise
      end

      result = controls.process_samples(mic_samples)

      expect(result.length).to eq(mic_samples.length)

      # AGC should adapt the levels
      stats = controls.detailed_statistics
      expect(stats[:agc_adjustments]).to be > 0
    end

    it "adapts to different environment conditions" do
      # Test quiet environment
      controls.apply_preset(:quiet_environment)
      quiet_samples = Array.new(100, 0.05)
      controls.process_samples(quiet_samples)
      quiet_stats = controls.detailed_statistics

      # Test loud environment
      controls.apply_preset(:loud_environment)
      loud_samples = Array.new(100, 0.8)
      controls.process_samples(loud_samples)
      loud_stats = controls.detailed_statistics

      # Quiet environment should have higher effective gain
      expect(quiet_stats[:effective_gain]).to be > loud_stats[:effective_gain]
    end
  end
end
