# frozen_string_literal: true

require_relative "base"

module CliVisualizer
  module Visualizer
    # Frequency spectrum bar visualizer (equalizer-style)
    # Displays audio frequency data as vertical bars representing different frequency bands
    class Spectrum < Base
      # Spectrum-specific defaults
      DEFAULT_BANDS = 32
      DEFAULT_MIN_FREQUENCY = 20 # Hz
      DEFAULT_MAX_FREQUENCY = 20_000 # Hz
      DEFAULT_BAR_WIDTH = 2
      DEFAULT_BAR_SPACING = 1
      DEFAULT_SHOW_PEAKS = true
      DEFAULT_PEAK_HOLD_TIME = 1.0 # seconds
      DEFAULT_SHOW_LABELS = false

      # Bar characters for different intensities
      BAR_CHARS = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █].freeze
      PEAK_CHAR = "▄"
      SPACE_CHAR = " "

      attr_reader :bands, :min_frequency, :max_frequency, :bar_width, :bar_spacing, :show_peaks, :peak_hold_time, :show_labels

      def initialize(
        bands: DEFAULT_BANDS,
        min_frequency: DEFAULT_MIN_FREQUENCY,
        max_frequency: DEFAULT_MAX_FREQUENCY,
        bar_width: DEFAULT_BAR_WIDTH,
        bar_spacing: DEFAULT_BAR_SPACING,
        show_peaks: DEFAULT_SHOW_PEAKS,
        peak_hold_time: DEFAULT_PEAK_HOLD_TIME,
        show_labels: DEFAULT_SHOW_LABELS,
        **base_options
      )
        @bands = validate_positive_integer(bands, "Bands")
        @min_frequency = validate_positive_number(min_frequency, "Min frequency")
        @max_frequency = validate_positive_number(max_frequency, "Max frequency")
        @bar_width = validate_positive_integer(bar_width, "Bar width")
        @bar_spacing = validate_range(bar_spacing, 0, 10, "Bar spacing")
        @show_peaks = show_peaks
        @peak_hold_time = validate_positive_number(peak_hold_time, "Peak hold time")
        @show_labels = show_labels

        raise ArgumentError, "Max frequency must be greater than min frequency" if @max_frequency <= @min_frequency

        super(
          name: "Spectrum",
          description: "Frequency spectrum equalizer visualization",
          **base_options
        )
      end

      protected

      def initialize_visualizer
        # Frequency band configuration
        @frequency_bands = calculate_frequency_bands
        @band_magnitudes = Array.new(@bands, 0.0)
        @smoothed_magnitudes = Array.new(@bands, 0.0)

        # Peak tracking
        @peak_magnitudes = Array.new(@bands, 0.0)
        @peak_timestamps = Array.new(@bands, 0.0)

        # Display calculations
        calculate_display_layout
      end

      def process_frequency_analysis(frequency_data)
        return unless frequency_data.is_a?(Hash)
        return unless frequency_data[:frequencies] && frequency_data[:magnitudes]

        frequencies = frequency_data[:frequencies]
        magnitudes = frequency_data[:magnitudes]

        # Map frequency bins to our display bands
        update_band_magnitudes(frequencies, magnitudes)

        # Apply smoothing
        apply_smoothing

        # Update peaks
        update_peaks if @show_peaks
      end

      def generate_frame_data
        {
          type: :spectrum,
          width: @width,
          height: @height,
          bands: @bands,
          band_data: generate_band_data,
          labels: @show_labels ? generate_frequency_labels : nil,
          peaks: @show_peaks ? @peak_magnitudes.dup : nil
        }
      end

      def handle_resize(_new_width, _new_height)
        calculate_display_layout
      end

      def supported_features
        %i[frequency_analysis smoothing scaling peak_hold]
      end

      def default_config
        super.merge(
          bands: DEFAULT_BANDS,
          min_frequency: DEFAULT_MIN_FREQUENCY,
          max_frequency: DEFAULT_MAX_FREQUENCY,
          bar_width: DEFAULT_BAR_WIDTH,
          bar_spacing: DEFAULT_BAR_SPACING,
          show_peaks: DEFAULT_SHOW_PEAKS,
          peak_hold_time: DEFAULT_PEAK_HOLD_TIME,
          show_labels: DEFAULT_SHOW_LABELS
        )
      end

      private

      # Calculate frequency band boundaries using logarithmic distribution
      def calculate_frequency_bands
        return [] if @bands <= 0

        # Use logarithmic distribution for more natural frequency spacing
        log_min = Math.log10(@min_frequency)
        log_max = Math.log10(@max_frequency)
        log_step = (log_max - log_min) / @bands

        (0...@bands).map do |i|
          low_freq = 10**(log_min + (i * log_step))
          high_freq = 10**(log_min + ((i + 1) * log_step))
          {
            low: low_freq,
            high: high_freq,
            center: Math.sqrt(low_freq * high_freq) # Geometric mean
          }
        end
      end

      # Update band magnitudes from frequency analysis data
      def update_band_magnitudes(frequencies, magnitudes)
        @band_magnitudes.fill(0.0)

        # For each frequency bin, add its magnitude to the appropriate band(s)
        frequencies.each_with_index do |freq, bin_index|
          next if bin_index >= magnitudes.length

          magnitude = magnitudes[bin_index]
          next if magnitude <= 0

          # Find which band(s) this frequency belongs to
          @frequency_bands.each_with_index do |band, band_index|
            @band_magnitudes[band_index] += magnitude if freq >= band[:low] && freq <= band[:high]
          end
        end

        # Normalize by band width (optional - can be removed for raw accumulation)
        @frequency_bands.each_with_index do |band, band_index|
          band_width = band[:high] - band[:low]
          @band_magnitudes[band_index] /= Math.log10(band_width + 1) if band_width.positive?
        end
      end

      # Apply smoothing to band magnitudes
      def apply_smoothing
        @band_magnitudes.each_with_index do |magnitude, i|
          @smoothed_magnitudes[i] = smooth_value(@smoothed_magnitudes[i], magnitude)
        end
      end

      # Update peak tracking
      def update_peaks
        current_time = Time.now.to_f

        @smoothed_magnitudes.each_with_index do |magnitude, i|
          if magnitude > @peak_magnitudes[i]
            # New peak
            @peak_magnitudes[i] = magnitude
            @peak_timestamps[i] = current_time
          elsif current_time - @peak_timestamps[i] > @peak_hold_time
            # Peak has expired, decay it
            decay_rate = 0.1 # Adjust decay speed
            @peak_magnitudes[i] = [@peak_magnitudes[i] - decay_rate, magnitude].max
          end
        end
      end

      # Generate visual band data for rendering
      def generate_band_data
        max_magnitude = [@smoothed_magnitudes.max, 0.001].max # Avoid division by zero

        @smoothed_magnitudes.map.with_index do |magnitude, band_index|
          # Scale magnitude to display height
          normalized_magnitude = scale_value(magnitude, max_magnitude)
          bar_height = (normalized_magnitude * (@height - label_height)).round

          # Generate bar visualization
          bar_chars = generate_bar_chars(bar_height)

          # Add peak indicator if enabled
          peak_char = nil
          if @show_peaks && @peak_magnitudes[band_index] > magnitude
            peak_normalized = scale_value(@peak_magnitudes[band_index], max_magnitude)
            peak_height = (peak_normalized * (@height - label_height)).round
            peak_char = { height: peak_height, char: PEAK_CHAR }
          end

          {
            band: band_index,
            frequency: @frequency_bands[band_index],
            magnitude: magnitude,
            normalized_magnitude: normalized_magnitude,
            bar_height: bar_height,
            bar_chars: bar_chars,
            peak: peak_char
          }
        end
      end

      # Generate bar character representation for a given height
      def generate_bar_chars(height)
        return [] if height <= 0

        full_blocks = height / BAR_CHARS.length
        remainder = height % BAR_CHARS.length

        chars = []

        # Full intensity blocks
        full_blocks.times { chars << BAR_CHARS.last }

        # Partial block for remainder
        chars << BAR_CHARS[remainder - 1] if remainder.positive?

        chars
      end

      # Generate frequency labels if enabled
      def generate_frequency_labels
        return [] unless @show_labels

        label_bands = [@bands / 4, 8].min # Show up to 8 labels, space them out

        step = @bands / label_bands
        labels = []

        (0...label_bands).each do |i|
          band_index = i * step
          next if band_index >= @frequency_bands.length

          freq = @frequency_bands[band_index][:center]
          label = format_frequency(freq)
          position = calculate_label_position(band_index)

          labels << {
            band: band_index,
            frequency: freq,
            label: label,
            position: position
          }
        end

        labels
      end

      # Format frequency for display
      def format_frequency(freq)
        if freq >= 1000
          "#{(freq / 1000).round(1)}k"
        else
          "#{freq.round}Hz"
        end
      end

      # Calculate label position in display
      def calculate_label_position(band_index)
        band_width = @bar_width + @bar_spacing
        x_position = (band_index * band_width) + (@bar_width / 2)
        y_position = @height - 1 # Bottom row

        { x: x_position, y: y_position }
      end

      # Calculate display layout parameters
      def calculate_display_layout
        # Calculate how many bands can fit in the display width
        total_band_width = @bar_width + @bar_spacing
        max_bands_for_width = @width / total_band_width

        # Adjust bands if they don't fit
        if @bands > max_bands_for_width
          @effective_bands = max_bands_for_width
          @band_step = @bands.to_f / @effective_bands
        else
          @effective_bands = @bands
          @band_step = 1.0
        end

        # Calculate actual display dimensions
        @display_width = (@effective_bands * total_band_width) - @bar_spacing
        @display_height = @height - label_height
      end

      # Height reserved for labels
      def label_height
        @show_labels ? 1 : 0
      end

      # Configuration methods

      def set_bands(new_bands)
        @bands = validate_positive_integer(new_bands, "Bands")
        @frequency_bands = calculate_frequency_bands
        @band_magnitudes = Array.new(@bands, 0.0)
        @smoothed_magnitudes = Array.new(@bands, 0.0)
        @peak_magnitudes = Array.new(@bands, 0.0)
        @peak_timestamps = Array.new(@bands, 0.0)
        calculate_display_layout
      end

      def set_frequency_range(min_freq, max_freq)
        @min_frequency = validate_positive_number(min_freq, "Min frequency")
        @max_frequency = validate_positive_number(max_freq, "Max frequency")
        raise ArgumentError, "Max frequency must be greater than min frequency" if @max_frequency <= @min_frequency

        @frequency_bands = calculate_frequency_bands
      end

      def set_bar_style(width: nil, spacing: nil)
        @bar_width = validate_positive_integer(width, "Bar width") if width
        @bar_spacing = validate_range(spacing, 0, 10, "Bar spacing") if spacing
        calculate_display_layout
      end

      def set_peak_settings(show_peaks: nil, hold_time: nil)
        @show_peaks = show_peaks unless show_peaks.nil?
        @peak_hold_time = validate_positive_number(hold_time, "Peak hold time") if hold_time
      end

      def toggle_labels
        @show_labels = !@show_labels
        calculate_display_layout
      end

      # Utility methods

      # Get current band data for external use
      def current_band_data
        @smoothed_magnitudes.map.with_index do |magnitude, i|
          {
            band: i,
            frequency: @frequency_bands[i],
            magnitude: magnitude
          }
        end
      end

      # Get peak data for external use
      def current_peak_data
        return [] unless @show_peaks

        @peak_magnitudes.map.with_index do |peak, i|
          {
            band: i,
            frequency: @frequency_bands[i],
            peak_magnitude: peak,
            age: Time.now.to_f - @peak_timestamps[i]
          }
        end
      end

      # Reset peaks
      def reset_peaks
        @peak_magnitudes.fill(0.0)
        @peak_timestamps.fill(0.0)
      end
    end
  end
end
