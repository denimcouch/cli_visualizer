# frozen_string_literal: true

require "spec_helper"
require "cli_visualizer/audio/controls"
require "cli_visualizer/audio/source_manager"
require "cli_visualizer/audio/processor"
require "tempfile"

RSpec.describe CliVisualizer::Audio::Controls, :integration do
  let(:controls) { described_class.new }
  let(:source_manager) { CliVisualizer::Audio::SourceManager.new }
  let(:processor) { CliVisualizer::Audio::Processor.new }

  describe "complete audio pipeline with controls" do
    let(:temp_audio_file) { create_test_audio_file }

    before do
      source_manager.create_source("test_file", type: :file, file_path: temp_audio_file.path)
      source_manager.switch_to_source("test_file")
    end

    after do
      cleanup_temp_file(temp_audio_file)
    end

    it "integrates controls with source manager and processor pipeline" do
      processed_audio_chunks = []
      frequency_analysis_results = []
      control_level_changes = []

      # Set up the complete pipeline:
      # Source -> Controls -> Processor -> Results

      # 1. Controls receive level change notifications
      controls.on_level_change do |level_data|
        control_level_changes << level_data
      end

      # 2. Processor receives frequency analysis results
      processor.on_frequency_data do |freq_data|
        frequency_analysis_results << freq_data
      end

      # 3. Source manager audio flows through controls then to processor
      source_manager.on_audio_data do |raw_samples|
        # Apply audio controls
        controlled_samples = controls.process_samples(raw_samples)
        processed_audio_chunks << controlled_samples

        # Send to frequency analysis
        processor.process_samples(controlled_samples)
      end

      # Simulate audio flowing through the pipeline
      test_samples = generate_test_audio_samples(1024)
      source_manager.buffer_manager.write_to_buffer("main_audio", test_samples)

      # Verify the complete pipeline worked
      expect(processed_audio_chunks).not_to be_empty
      expect(frequency_analysis_results).not_to be_empty
      expect(control_level_changes).not_to be_empty

      # Verify data integrity through the pipeline
      expect(processed_audio_chunks.first.length).to eq(test_samples.length)
      expect(frequency_analysis_results.first).to include(:frequencies, :magnitudes, :phases)
      expect(control_level_changes.first).to include(:peak, :rms, :timestamp)
    end

    it "applies different presets to modify audio processing" do
      audio_results = {}

      # Test multiple presets and their effect on the audio
      %i[music_file live_input quiet_environment loud_environment].each do |preset|
        controls.apply_preset(preset)

        test_samples = generate_test_audio_samples(512)
        result = controls.process_samples(test_samples)

        audio_results[preset] = {
          peak: result.map(&:abs).max,
          rms: calculate_rms(result),
          settings: controls.current_settings
        }
      end

      # Different presets should produce different results
      peaks = audio_results.values.map { |r| r[:peak] }
      expect(peaks.uniq.length).to be > 1 # Should have different peak levels

      # Quiet environment should have higher effective gain
      quiet_gain = audio_results[:quiet_environment][:settings][:gain]
      loud_gain = audio_results[:loud_environment][:settings][:gain]
      expect(quiet_gain).to be > loud_gain
    end

    it "provides real-time gain adjustment during audio processing" do
      gain_changes = []
      level_history = []

      # Monitor gain changes
      controls.on_gain_change { |data| gain_changes << data }
      controls.on_level_change { |data| level_history << data }

      # Set up automatic processing
      source_manager.on_audio_data do |samples|
        # Apply controls and monitor levels
        result = controls.process_samples(samples)

        # Simulate real-time gain adjustment based on levels
        if result.map(&:abs).max > 0.8
          controls.set_gain(controls.gain * 0.9) # Reduce gain if too loud
        elsif result.map(&:abs).max < 0.1
          controls.set_gain(controls.gain * 1.1) # Increase gain if too quiet
        end
      end

      # Simulate varying audio levels
      loud_samples = Array.new(100, 0.9)
      quiet_samples = Array.new(100, 0.05)

      source_manager.buffer_manager.write_to_buffer("main_audio", loud_samples)
      source_manager.buffer_manager.write_to_buffer("main_audio", quiet_samples)

      # Should have triggered some gain changes
      expect(gain_changes).not_to be_empty
      expect(level_history).not_to be_empty
    end

    it "maintains audio quality through the complete processing chain" do
      # Test that audio quality is preserved through the entire pipeline
      original_samples = generate_music_like_samples(2048)

      # Process through the complete chain
      source_manager.on_audio_data do |samples|
        # Controls processing
        controlled = controls.process_samples(samples)

        # Frequency analysis
        processor.process_samples(controlled)
      end

      # Apply conservative settings to preserve quality
      controls.apply_preset(:music_file)

      # Send audio through pipeline
      source_manager.buffer_manager.write_to_buffer("main_audio", original_samples)

      # Verify no significant distortion
      stats = controls.detailed_statistics
      expect(stats[:clipped_samples]).to eq(0) # No clipping
      expect(stats[:processed_samples]).to be > 0
    end
  end

  describe "adaptive audio processing scenarios" do
    it "adapts to changing audio characteristics in real-time" do
      adaptation_log = []

      # Set up adaptive processing
      controls.enable_agc(true)
      controls.set_agc_timing(attack: 0.1, release: 0.3)

      # Monitor adaptation
      controls.on_level_change do |data|
        current_levels = controls.current_levels
        adaptation_log << {
          timestamp: data[:timestamp],
          input_rms: data[:rms],
          agc_gain: current_levels[:agc_gain],
          effective_gain: controls.detailed_statistics[:effective_gain]
        }
      end

      # Simulate changing audio environment
      scenarios = [
        { samples: Array.new(200, 0.1), name: "quiet" },
        { samples: Array.new(200, 0.8), name: "loud" },
        { samples: Array.new(200, 0.05), name: "very_quiet" },
        { samples: Array.new(200, 0.3), name: "medium" }
      ]

      scenarios.each do |scenario|
        10.times { controls.process_samples(scenario[:samples]) }
      end

      # AGC should have adapted to different levels
      expect(adaptation_log).not_to be_empty

      # Should show variation in AGC gain
      agc_gains = adaptation_log.map { |entry| entry[:agc_gain] }
      expect(agc_gains.uniq.length).to be > 1
    end

    it "handles audio source switching with maintained control settings" do
      temp_file1 = create_test_audio_file("source1")
      temp_file2 = create_test_audio_file("source2")

      source_manager.create_source("source1", type: :file, file_path: temp_file1.path)
      source_manager.create_source("source2", type: :file, file_path: temp_file2.path)

      # Configure controls for specific scenario
      controls.apply_preset(:live_input)
      controls.set_gain(1.5)
      controls.set_sensitivity(2.0)

      initial_settings = controls.current_settings

      processing_results = []

      # Set up processing pipeline
      source_manager.on_audio_data do |samples|
        result = controls.process_samples(samples)
        processing_results << {
          source: source_manager.current_source_info[:id],
          peak: result.map(&:abs).max,
          settings: controls.current_settings
        }
      end

      # Process audio from first source
      source_manager.switch_to_source("source1")
      test_samples1 = generate_test_audio_samples(256)
      source_manager.buffer_manager.write_to_buffer("main_audio", test_samples1)

      # Switch to second source
      source_manager.switch_to_source("source2")
      test_samples2 = generate_test_audio_samples(256)
      source_manager.buffer_manager.write_to_buffer("main_audio", test_samples2)

      # Controls settings should remain consistent across source switches
      final_settings = controls.current_settings
      expect(final_settings[:gain]).to eq(initial_settings[:gain])
      expect(final_settings[:sensitivity]).to eq(initial_settings[:sensitivity])

      # Should have processed audio from both sources
      source1_results = processing_results.select { |r| r[:source] == "source1" }
      source2_results = processing_results.select { |r| r[:source] == "source2" }

      expect(source1_results).not_to be_empty
      expect(source2_results).not_to be_empty

      cleanup_temp_file(temp_file1)
      cleanup_temp_file(temp_file2)
    end

    it "optimizes for different audio content types automatically" do
      content_adaptations = {}

      # Test different content types
      content_types = {
        speech: generate_speech_like_samples(1000),
        music: generate_music_like_samples(1000),
        noise: generate_noise_samples(1000),
        silence: Array.new(1000, 0.01)
      }

      content_types.each do |type, samples|
        # Reset controls
        controls.apply_preset(:live_input)

        # Process samples and let AGC adapt
        20.times { controls.process_samples(samples) }

        # Record adaptation results
        content_adaptations[type] = {
          final_gain: controls.current_levels[:agc_gain],
          settings: controls.current_settings,
          stats: controls.detailed_statistics
        }
      end

      # Different content should result in different adaptations
      agc_gains = content_adaptations.values.map { |a| a[:final_gain] }
      expect(agc_gains.uniq.length).to be > 1

      # Silence should have highest AGC gain (trying to amplify)
      silence_gain = content_adaptations[:silence][:final_gain]
      music_gain = content_adaptations[:music][:final_gain]
      expect(silence_gain).to be > music_gain
    end
  end

  describe "performance and stability" do
    it "maintains performance under continuous processing load" do
      start_time = Time.now
      total_samples_processed = 0

      # Continuous processing for a short duration
      end_time = start_time + 0.1 # 100ms of processing

      while Time.now < end_time
        samples = generate_test_audio_samples(256)
        controls.process_samples(samples)
        total_samples_processed += samples.length
      end

      processing_time = Time.now - start_time

      # Should process significant amounts of audio efficiently
      expect(total_samples_processed).to be > 1000
      expect(processing_time).to be < 0.2 # Should complete quickly

      # Statistics should reflect the processing
      stats = controls.statistics
      expect(stats[:processed_samples]).to eq(total_samples_processed)
    end

    it "remains stable under extreme parameter changes" do
      # Rapidly change parameters while processing
      processing_thread = Thread.new do
        100.times do
          samples = generate_test_audio_samples(128)
          controls.process_samples(samples)
          sleep(0.001)
        end
      end

      control_thread = Thread.new do
        20.times do |i|
          controls.set_gain(0.1 + (i % 10) * 0.2)
          controls.set_sensitivity(0.5 + (i % 5) * 0.3)

          # Toggle features
          controls.enable_agc(i.even?)
          controls.enable_compressor(i.odd?)

          sleep(0.005)
        end
      end

      expect { [processing_thread, control_thread].each(&:join) }.not_to raise_error

      # Should still be functional after stress test
      test_result = controls.process_samples([0.1, 0.2, 0.3])
      expect(test_result).to be_an(Array)
      expect(test_result.length).to eq(3)
    end
  end

  # Helper methods
  private

  def create_test_audio_file(name = "test")
    temp_file = Tempfile.new(["#{name}_audio", ".wav"])
    temp_file.write("RIFF#{[44].pack("V")}WAVE")
    temp_file.close
    temp_file
  end

  def cleanup_temp_file(temp_file)
    temp_file.unlink if temp_file
  rescue StandardError
    # Ignore cleanup errors
  end

  def generate_test_audio_samples(count)
    Array.new(count) { |i| Math.sin(2 * Math::PI * i / 100.0) * 0.5 }
  end

  def generate_music_like_samples(count)
    Array.new(count) do |i|
      # Complex waveform simulating music
      fundamental = 0.3 * Math.sin(2 * Math::PI * i / 200.0)
      harmonics = 0.1 * Math.sin(2 * Math::PI * i / 100.0) + 0.05 * Math.sin(2 * Math::PI * i / 67.0)
      dynamics = 0.5 + 0.4 * Math.sin(2 * Math::PI * i / 1000.0)

      (fundamental + harmonics) * dynamics
    end
  end

  def generate_speech_like_samples(count)
    Array.new(count) do |i|
      # Simulated speech patterns with formants
      base_freq = 100 + 50 * Math.sin(2 * Math::PI * i / 500.0)
      formant1 = 0.4 * Math.sin(2 * Math::PI * i * base_freq / 44_100.0)
      formant2 = 0.2 * Math.sin(2 * Math::PI * i * base_freq * 2.5 / 44_100.0)
      envelope = 0.3 + 0.5 * Math.sin(2 * Math::PI * i / 200.0).abs

      (formant1 + formant2) * envelope
    end
  end

  def generate_noise_samples(count)
    Array.new(count) { (rand - 0.5) * 0.4 }
  end

  def calculate_rms(samples)
    return 0.0 if samples.empty?

    sum_of_squares = samples.sum { |sample| sample * sample }
    Math.sqrt(sum_of_squares / samples.length)
  end
end
