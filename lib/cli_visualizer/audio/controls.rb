# frozen_string_literal: true

module CliVisualizer
  module Audio
    # Audio controls for gain, sensitivity, and audio processing adjustments
    # Provides real-time control over audio levels and visualization responsiveness
    class Controls
      # Default settings
      DEFAULT_GAIN = 1.0
      DEFAULT_SENSITIVITY = 1.0
      DEFAULT_AGC_ENABLED = false
      DEFAULT_AGC_TARGET = 0.7
      DEFAULT_AGC_ATTACK = 0.1
      DEFAULT_AGC_RELEASE = 0.3
      DEFAULT_LIMITER_ENABLED = true
      DEFAULT_LIMITER_THRESHOLD = 0.95
      DEFAULT_COMPRESSOR_ENABLED = false
      DEFAULT_COMPRESSOR_RATIO = 4.0
      DEFAULT_COMPRESSOR_THRESHOLD = 0.8
      DEFAULT_NOISE_GATE_ENABLED = false
      DEFAULT_NOISE_GATE_THRESHOLD = 0.01

      # Limits
      MIN_GAIN = 0.0
      MAX_GAIN = 10.0
      MIN_SENSITIVITY = 0.1
      MAX_SENSITIVITY = 5.0

      attr_reader :gain, :sensitivity, :agc_enabled, :agc_target, :agc_attack, :agc_release, :limiter_enabled,
                  :limiter_threshold, :compressor_enabled, :compressor_ratio, :compressor_threshold, :noise_gate_enabled, :noise_gate_threshold, :statistics

      def initialize(
        gain: DEFAULT_GAIN,
        sensitivity: DEFAULT_SENSITIVITY,
        agc_enabled: DEFAULT_AGC_ENABLED,
        agc_target: DEFAULT_AGC_TARGET,
        agc_attack: DEFAULT_AGC_ATTACK,
        agc_release: DEFAULT_AGC_RELEASE,
        limiter_enabled: DEFAULT_LIMITER_ENABLED,
        limiter_threshold: DEFAULT_LIMITER_THRESHOLD,
        compressor_enabled: DEFAULT_COMPRESSOR_ENABLED,
        compressor_ratio: DEFAULT_COMPRESSOR_RATIO,
        compressor_threshold: DEFAULT_COMPRESSOR_THRESHOLD,
        noise_gate_enabled: DEFAULT_NOISE_GATE_ENABLED,
        noise_gate_threshold: DEFAULT_NOISE_GATE_THRESHOLD
      )
        # Basic controls
        @gain = validate_gain(gain)
        @sensitivity = validate_sensitivity(sensitivity)

        # Automatic Gain Control
        @agc_enabled = agc_enabled
        @agc_target = validate_range(agc_target, 0.1, 1.0, "AGC target")
        @agc_attack = validate_range(agc_attack, 0.01, 1.0, "AGC attack")
        @agc_release = validate_range(agc_release, 0.01, 2.0, "AGC release")
        @agc_gain = 1.0
        @agc_envelope = 0.0

        # Peak Limiter
        @limiter_enabled = limiter_enabled
        @limiter_threshold = validate_range(limiter_threshold, 0.1, 1.0, "Limiter threshold")
        @limiter_gain_reduction = 0.0

        # Compressor
        @compressor_enabled = compressor_enabled
        @compressor_ratio = validate_range(compressor_ratio, 1.0, 20.0, "Compressor ratio")
        @compressor_threshold = validate_range(compressor_threshold, 0.1, 1.0, "Compressor threshold")
        @compressor_gain_reduction = 0.0

        # Noise Gate
        @noise_gate_enabled = noise_gate_enabled
        @noise_gate_threshold = validate_range(noise_gate_threshold, 0.001, 0.1, "Noise gate threshold")
        @noise_gate_open = true

        # Statistics and monitoring
        @statistics = {
          processed_samples: 0,
          peak_level: 0.0,
          rms_level: 0.0,
          gain_reductions: 0,
          agc_adjustments: 0,
          gate_closures: 0,
          clipped_samples: 0
        }

        # Thread safety
        @mutex = Mutex.new

        # Callbacks
        @level_callbacks = []
        @gain_change_callbacks = []
      end

      # Process audio samples through the control chain
      def process_samples(samples)
        return samples if samples.empty?

        @mutex.synchronize do
          processed = samples.dup

          # 1. Apply manual gain
          processed = apply_gain(processed, @gain) if @gain != 1.0

          # 2. Noise Gate
          processed = apply_noise_gate(processed) if @noise_gate_enabled

          # 3. Compressor
          processed = apply_compressor(processed) if @compressor_enabled

          # 4. Automatic Gain Control
          processed = apply_agc(processed) if @agc_enabled

          # 5. Peak Limiter (always last in chain)
          processed = apply_limiter(processed) if @limiter_enabled

          # 6. Apply sensitivity scaling
          processed = apply_sensitivity(processed) if @sensitivity != 1.0

          # Update statistics
          update_statistics(processed)

          # Notify callbacks
          notify_level_callbacks(processed)

          processed
        end
      end

      # Gain control methods
      def set_gain(new_gain)
        old_gain = @gain
        @gain = validate_gain(new_gain)
        notify_gain_change_callbacks(old_gain, @gain) if old_gain != @gain
      end

      def set_sensitivity(new_sensitivity)
        @sensitivity = validate_sensitivity(new_sensitivity)
      end

      # AGC controls
      def enable_agc(enabled = true)
        @agc_enabled = enabled
      end

      def disable_agc
        enable_agc(false)
      end

      def set_agc_target(target)
        @agc_target = validate_range(target, 0.1, 1.0, "AGC target")
      end

      def set_agc_timing(attack:, release:)
        @agc_attack = validate_range(attack, 0.01, 1.0, "AGC attack")
        @agc_release = validate_range(release, 0.01, 2.0, "AGC release")
      end

      # Limiter controls
      def enable_limiter(enabled = true)
        @limiter_enabled = enabled
      end

      def disable_limiter
        enable_limiter(false)
      end

      def set_limiter_threshold(threshold)
        @limiter_threshold = validate_range(threshold, 0.1, 1.0, "Limiter threshold")
      end

      # Compressor controls
      def enable_compressor(enabled = true)
        @compressor_enabled = enabled
      end

      def disable_compressor
        enable_compressor(false)
      end

      def set_compressor_settings(ratio:, threshold:)
        @compressor_ratio = validate_range(ratio, 1.0, 20.0, "Compressor ratio")
        @compressor_threshold = validate_range(threshold, 0.1, 1.0, "Compressor threshold")
      end

      # Noise gate controls
      def enable_noise_gate(enabled = true)
        @noise_gate_enabled = enabled
      end

      def disable_noise_gate
        enable_noise_gate(false)
      end

      def set_noise_gate_threshold(threshold)
        @noise_gate_threshold = validate_range(threshold, 0.001, 0.1, "Noise gate threshold")
      end

      # Callback registration
      def on_level_change(&block)
        @level_callbacks << block if block
      end

      def on_gain_change(&block)
        @gain_change_callbacks << block if block
      end

      def clear_callbacks
        @level_callbacks.clear
        @gain_change_callbacks.clear
      end

      # Get current audio levels
      def current_levels
        {
          peak: @statistics[:peak_level],
          rms: @statistics[:rms_level],
          agc_gain: @agc_gain,
          limiter_reduction: @limiter_gain_reduction,
          compressor_reduction: @compressor_gain_reduction,
          gate_open: @noise_gate_open
        }
      end

      # Get comprehensive statistics
      def detailed_statistics
        @statistics.merge(
          effective_gain: @gain * @agc_gain,
          total_gain_reduction: @limiter_gain_reduction + @compressor_gain_reduction,
          current_levels: current_levels,
          settings: current_settings
        )
      end

      # Get current settings
      def current_settings
        {
          gain: @gain,
          sensitivity: @sensitivity,
          agc: {
            enabled: @agc_enabled,
            target: @agc_target,
            attack: @agc_attack,
            release: @agc_release
          },
          limiter: {
            enabled: @limiter_enabled,
            threshold: @limiter_threshold
          },
          compressor: {
            enabled: @compressor_enabled,
            ratio: @compressor_ratio,
            threshold: @compressor_threshold
          },
          noise_gate: {
            enabled: @noise_gate_enabled,
            threshold: @noise_gate_threshold
          }
        }
      end

      # Reset all statistics
      def reset_statistics
        @statistics = {
          processed_samples: 0,
          peak_level: 0.0,
          rms_level: 0.0,
          gain_reductions: 0,
          agc_adjustments: 0,
          gate_closures: 0,
          clipped_samples: 0
        }
      end

      # Preset configurations
      def apply_preset(preset_name)
        case preset_name.to_sym
        when :live_input
          apply_live_input_preset
        when :music_file
          apply_music_file_preset
        when :quiet_environment
          apply_quiet_environment_preset
        when :loud_environment
          apply_loud_environment_preset
        when :disabled
          apply_disabled_preset
        else
          raise ArgumentError, "Unknown preset: #{preset_name}"
        end
      end

      private

      # Audio processing methods
      def apply_gain(samples, gain_value)
        samples.map { |sample| sample * gain_value }
      end

      def apply_sensitivity(samples)
        samples.map { |sample| sample * @sensitivity }
      end

      def apply_noise_gate(samples)
        rms = calculate_rms(samples)

        if rms < @noise_gate_threshold
          unless @noise_gate_open == false
            @noise_gate_open = false
            @statistics[:gate_closures] += 1
          end
          # Gate closed - attenuate signal
          samples.map { |sample| sample * 0.01 }
        else
          @noise_gate_open = true
          samples
        end
      end

      def apply_compressor(samples)
        return samples unless @compressor_enabled

        peak = samples.map(&:abs).max
        return samples if peak <= @compressor_threshold

        # Calculate gain reduction
        over_threshold = peak - @compressor_threshold
        gain_reduction = over_threshold / @compressor_ratio
        @compressor_gain_reduction = gain_reduction

        # Apply compression
        compression_gain = 1.0 - gain_reduction
        @statistics[:gain_reductions] += 1

        samples.map { |sample| sample * compression_gain }
      end

      def apply_agc(samples)
        return samples unless @agc_enabled

        # Calculate current RMS level
        current_rms = calculate_rms(samples)

        # Update envelope follower
        @agc_envelope += if current_rms > @agc_envelope
                           (@agc_attack * (current_rms - @agc_envelope))
                         else
                           (@agc_release * (current_rms - @agc_envelope))
                         end

        # Calculate AGC gain adjustment
        if @agc_envelope > 0.001
          desired_gain = @agc_target / @agc_envelope
          old_agc_gain = @agc_gain
          @agc_gain += 0.1 * (desired_gain - @agc_gain) # Smooth adjustment
          @agc_gain = [@agc_gain, 0.1, 10.0].sort[1] # Clamp between 0.1 and 10.0

          @statistics[:agc_adjustments] += 1 if (@agc_gain - old_agc_gain).abs > 0.01
        end

        apply_gain(samples, @agc_gain)
      end

      def apply_limiter(samples)
        return samples unless @limiter_enabled

        peak = samples.map(&:abs).max
        return samples if peak <= @limiter_threshold

        # Calculate limiter gain reduction
        @limiter_gain_reduction = peak - @limiter_threshold
        limiter_gain = @limiter_threshold / peak
        @statistics[:gain_reductions] += 1

        # Apply limiting
        limited = samples.map { |sample| sample * limiter_gain }

        # Count clipped samples
        @statistics[:clipped_samples] += samples.count { |sample| sample.abs > 1.0 }

        limited
      end

      def calculate_rms(samples)
        return 0.0 if samples.empty?

        sum_of_squares = samples.sum { |sample| sample * sample }
        Math.sqrt(sum_of_squares / samples.length)
      end

      def update_statistics(samples)
        @statistics[:processed_samples] += samples.length

        return unless samples.any?

        current_peak = samples.map(&:abs).max
        current_rms = calculate_rms(samples)

        @statistics[:peak_level] = [@statistics[:peak_level], current_peak].max
        @statistics[:rms_level] = (0.9 * @statistics[:rms_level]) + (0.1 * current_rms)
      end

      def notify_level_callbacks(samples)
        return if @level_callbacks.empty?

        level_data = {
          peak: samples.map(&:abs).max,
          rms: calculate_rms(samples),
          timestamp: Time.now
        }

        @level_callbacks.each { |callback| callback.call(level_data) }
      rescue StandardError => e
        # Handle callback errors gracefully
        puts "Level callback error: #{e.message}" if $VERBOSE
      end

      def notify_gain_change_callbacks(old_gain, new_gain)
        return if @gain_change_callbacks.empty?

        change_data = {
          old_gain: old_gain,
          new_gain: new_gain,
          timestamp: Time.now
        }

        @gain_change_callbacks.each { |callback| callback.call(change_data) }
      rescue StandardError => e
        puts "Gain change callback error: #{e.message}" if $VERBOSE
      end

      # Validation methods
      def validate_gain(gain)
        validate_range(gain, MIN_GAIN, MAX_GAIN, "Gain")
      end

      def validate_sensitivity(sensitivity)
        validate_range(sensitivity, MIN_SENSITIVITY, MAX_SENSITIVITY, "Sensitivity")
      end

      def validate_range(value, min_val, max_val, name)
        raise ArgumentError, "#{name} must be between #{min_val} and #{max_val}" if value < min_val || value > max_val

        value.to_f
      end

      # Preset configurations
      def apply_live_input_preset
        @gain = 1.2
        @sensitivity = 1.5
        enable_agc(true)
        @agc_target = 0.7
        @agc_attack = 0.05
        @agc_release = 0.2
        enable_limiter(true)
        @limiter_threshold = 0.9
        enable_compressor(true)
        @compressor_ratio = 3.0
        @compressor_threshold = 0.75
        enable_noise_gate(true)
        @noise_gate_threshold = 0.005
      end

      def apply_music_file_preset
        @gain = 1.0
        @sensitivity = 1.0
        enable_agc(false)
        enable_limiter(true)
        @limiter_threshold = 0.95
        disable_compressor
        disable_noise_gate
      end

      def apply_quiet_environment_preset
        @gain = 2.0
        @sensitivity = 2.0
        enable_agc(true)
        @agc_target = 0.8
        @agc_attack = 0.02
        @agc_release = 0.5
        enable_limiter(true)
        @limiter_threshold = 0.85
        enable_compressor(true)
        @compressor_ratio = 6.0
        @compressor_threshold = 0.6
        enable_noise_gate(true)
        @noise_gate_threshold = 0.002
      end

      def apply_loud_environment_preset
        @gain = 0.7
        @sensitivity = 0.8
        enable_agc(true)
        @agc_target = 0.6
        @agc_attack = 0.1
        @agc_release = 0.1
        enable_limiter(true)
        @limiter_threshold = 0.8
        enable_compressor(true)
        @compressor_ratio = 8.0
        @compressor_threshold = 0.5
        disable_noise_gate
      end

      def apply_disabled_preset
        @gain = 1.0
        @sensitivity = 1.0
        disable_agc
        disable_limiter
        disable_compressor
        disable_noise_gate
      end
    end
  end
end
