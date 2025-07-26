# frozen_string_literal: true

require_relative "base"

module CliVisualizer
  module Visualizer
    # Waveform pattern visualization engine
    # Displays time-domain audio data as oscilloscope-style waveforms
    class Waveform < Base
      # Waveform-specific defaults
      DEFAULT_CHANNELS = :stereo    # :mono, :stereo, :left, :right
      DEFAULT_STYLE = :line         # :line, :filled, :dots, :bars
      DEFAULT_AMPLITUDE_SCALE = 1.0
      DEFAULT_TIME_SCALE = 1.0
      DEFAULT_CENTER_LINE = true
      DEFAULT_GRID_ENABLED = false
      DEFAULT_TRIGGER_ENABLED = false
      DEFAULT_TRIGGER_LEVEL = 0.1

      # Visual characters for different styles
      WAVEFORM_CHARS = {
        line: %w[─ ╱ ╲ │ ╳ ╰ ╯ ╭ ╮].freeze,
        filled: %w[▀ ▄ █ ▌ ▐ ▇ ▆ ▅ ▃ ▂ ▁].freeze,
        dots: %w[· ∘ ○ ● ◦ ◯ ⦾ ⦿].freeze,
        bars: %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █].freeze
      }.freeze

      CENTER_CHAR = "─"
      GRID_CHAR = "┼"
      TRIGGER_CHAR = "▶"

      attr_reader :channels, :style, :amplitude_scale, :time_scale, :center_line, :grid_enabled, :trigger_enabled, :trigger_level

      def initialize(
        channels: DEFAULT_CHANNELS,
        style: DEFAULT_STYLE,
        amplitude_scale: DEFAULT_AMPLITUDE_SCALE,
        time_scale: DEFAULT_TIME_SCALE,
        center_line: DEFAULT_CENTER_LINE,
        grid_enabled: DEFAULT_GRID_ENABLED,
        trigger_enabled: DEFAULT_TRIGGER_ENABLED,
        trigger_level: DEFAULT_TRIGGER_LEVEL,
        **base_options
      )
        @channels = validate_channels(channels)
        @style = validate_style(style)
        @amplitude_scale = validate_positive_number(amplitude_scale, "Amplitude scale")
        @time_scale = validate_positive_number(time_scale, "Time scale")
        @center_line = center_line
        @grid_enabled = grid_enabled
        @trigger_enabled = trigger_enabled
        @trigger_level = validate_range(trigger_level, -1.0, 1.0, "Trigger level")

        super(
          name: "Waveform",
          description: "Time-domain waveform oscilloscope visualization",
          **base_options
        )
      end

      protected

      def initialize_visualizer
        # Sample buffer for waveform display
        samples_needed = (@width * @time_scale).round
        @sample_buffer = Array.new(samples_needed, 0.0)
        @left_buffer = Array.new(samples_needed, 0.0)
        @right_buffer = Array.new(samples_needed, 0.0)

        # Trigger detection
        @trigger_position = 0
        @last_trigger_time = 0.0
        @trigger_history = []

        # Display calculation
        calculate_display_parameters
      end

      def process_audio_data(samples)
        return if samples.empty?

        # Convert to stereo if needed
        left_samples, right_samples = extract_channels(samples)

        # Update sample buffers
        update_sample_buffers(left_samples, right_samples)

        # Handle triggering if enabled
        update_trigger_detection(left_samples) if @trigger_enabled
      end

      def generate_frame_data
        {
          type: :waveform,
          width: @width,
          height: @height,
          channels: @channels,
          style: @style,
          waveform_data: generate_waveform_data,
          center_line: @center_line,
          grid: @grid_enabled ? generate_grid_data : nil,
          trigger: @trigger_enabled ? generate_trigger_data : nil
        }
      end

      def handle_resize(new_width, new_height)
        samples_needed = (new_width * @time_scale).round
        @sample_buffer = Array.new(samples_needed, 0.0)
        @left_buffer = Array.new(samples_needed, 0.0)
        @right_buffer = Array.new(samples_needed, 0.0)
        calculate_display_parameters
      end

      def supported_features
        %i[time_domain_analysis channels amplitude_scaling oscilloscope_trigger]
      end

      def default_config
        super.merge(
          channels: DEFAULT_CHANNELS,
          style: DEFAULT_STYLE,
          amplitude_scale: DEFAULT_AMPLITUDE_SCALE,
          time_scale: DEFAULT_TIME_SCALE,
          center_line: DEFAULT_CENTER_LINE,
          grid_enabled: DEFAULT_GRID_ENABLED,
          trigger_enabled: DEFAULT_TRIGGER_ENABLED,
          trigger_level: DEFAULT_TRIGGER_LEVEL
        )
      end

      private

      # Extract left and right channels from sample data
      def extract_channels(samples)
        case samples.first
        when Array
          # Stereo samples: [[left, right], [left, right], ...]
          left = samples.map(&:first)
          right = samples.map(&:last)
        when Numeric
          # Mono samples: [sample, sample, sample, ...]
          left = samples
          right = samples.dup
        else
          # Unknown format, treat as mono
          left = samples
          right = samples.dup
        end

        [left, right]
      end

      # Update internal sample buffers
      def update_sample_buffers(left_samples, right_samples)
        # Add new samples to buffers
        @left_buffer.concat(left_samples)
        @right_buffer.concat(right_samples)

        # Maintain buffer size
        samples_needed = (@width * @time_scale).round
        while @left_buffer.length > samples_needed
          @left_buffer.shift
          @right_buffer.shift
        end

        # Update main buffer based on channel configuration
        @sample_buffer = case @channels
                         when :left
                           @left_buffer.dup
                         when :right
                           @right_buffer.dup
                         when :mono
                           @left_buffer.zip(@right_buffer).map { |l, r| (l + r) / 2.0 }
                         when :stereo
                           @left_buffer.dup # Default to left for main buffer
                         else
                           @left_buffer.dup
                         end
      end

      # Update trigger detection and positioning
      def update_trigger_detection(samples)
        current_time = Time.now.to_f

        samples.each_with_index do |sample, index|
          # Look for rising edge trigger
          next unless sample > @trigger_level &&
                      @sample_buffer.length > index &&
                      @sample_buffer[-(samples.length - index)] <= @trigger_level

          # Found trigger, record it
          trigger_time = current_time + ((index.to_f / samples.length) * (1.0 / 60.0)) # Approximate timing

          # Avoid rapid retriggering
          next unless trigger_time - @last_trigger_time > 0.1 # 100ms minimum

          @trigger_position = @sample_buffer.length - samples.length + index
          @last_trigger_time = trigger_time
          @trigger_history << { time: trigger_time, position: @trigger_position }
          @trigger_history.shift if @trigger_history.length > 10
        end
      end

      # Generate waveform visualization data
      def generate_waveform_data
        case @channels
        when :stereo
          generate_stereo_waveform
        else
          generate_mono_waveform
        end
      end

      # Generate mono waveform data
      def generate_mono_waveform
        return [] if @sample_buffer.empty?

        points = []
        x_step = @width.to_f / @sample_buffer.length

        @sample_buffer.each_with_index do |sample, index|
          x = (index * x_step).round
          y = sample_to_y_coordinate(sample * @amplitude_scale)

          char = select_waveform_char(sample, index)

          points << {
            x: x,
            y: y,
            sample: sample,
            char: char,
            amplitude: sample * @amplitude_scale
          }
        end

        smooth_waveform_points(points)
      end

      # Generate stereo waveform data
      def generate_stereo_waveform
        return [] if @left_buffer.empty? || @right_buffer.empty?

        left_points = []
        right_points = []
        x_step = @width.to_f / @left_buffer.length

        # Split display height between channels
        left_center = @height / 4
        right_center = 3 * @height / 4

        @left_buffer.each_with_index do |sample, index|
          x = (index * x_step).round

          # Left channel (top half)
          left_y = left_center + (sample * @amplitude_scale * left_center / 2).round
          left_char = select_waveform_char(sample, index)

          left_points << {
            x: x,
            y: left_y.clamp(0, (@height / 2) - 1),
            sample: sample,
            char: left_char,
            channel: :left,
            amplitude: sample * @amplitude_scale
          }
        end

        @right_buffer.each_with_index do |sample, index|
          x = (index * x_step).round

          # Right channel (bottom half)
          right_y = right_center + (sample * @amplitude_scale * right_center / 4).round
          right_char = select_waveform_char(sample, index)

          right_points << {
            x: x,
            y: right_y.clamp(@height / 2, @height - 1),
            sample: sample,
            char: right_char,
            channel: :right,
            amplitude: sample * @amplitude_scale
          }
        end

        {
          left: smooth_waveform_points(left_points),
          right: smooth_waveform_points(right_points)
        }
      end

      # Convert sample value to Y coordinate
      def sample_to_y_coordinate(sample)
        # Center line is at height/2, scale sample to fill display
        center_y = @height / 2
        sample_y = (sample * center_y).round
        (center_y - sample_y).clamp(0, @height - 1)
      end

      # Select appropriate character for waveform style
      def select_waveform_char(sample, index)
        chars = WAVEFORM_CHARS[@style] || WAVEFORM_CHARS[:line]

        case @style
        when :line
          # Select based on slope and amplitude
          char_index = [(sample.abs * (chars.length - 1)).round, chars.length - 1].min
          chars[char_index]
        when :filled
          # Select based on amplitude level
          char_index = [(sample.abs * (chars.length - 1)).round, chars.length - 1].min
          chars[char_index]
        when :dots
          # Select based on amplitude and position
          char_index = [(sample.abs * (chars.length - 1)).round, chars.length - 1].min
          chars[char_index]
        when :bars
          # Select based on amplitude for bar style
          char_index = [(sample.abs * (chars.length - 1)).round, chars.length - 1].min
          chars[char_index]
        else
          chars.first
        end
      end

      # Smooth waveform points for better visual continuity
      def smooth_waveform_points(points)
        return points if points.length < 3

        smoothed = [points.first]

        (1...points.length - 1).each do |i|
          current = points[i]
          prev = points[i - 1]
          next_point = points[i + 1]

          # Simple smoothing by averaging Y coordinates
          smoothed_y = (prev[:y] + current[:y] + next_point[:y]) / 3

          smoothed << current.merge(y: smoothed_y.round.clamp(0, @height - 1))
        end

        smoothed << points.last
        smoothed
      end

      # Generate grid overlay data
      def generate_grid_data
        return [] unless @grid_enabled

        grid_lines = []

        # Horizontal grid lines (amplitude levels)
        (0...@height).step(@height / 4) do |y|
          grid_lines << {
            type: :horizontal,
            y: y,
            char: GRID_CHAR,
            label: amplitude_at_y(y)
          }
        end

        # Vertical grid lines (time divisions)
        (0...@width).step(@width / 8) do |x|
          grid_lines << {
            type: :vertical,
            x: x,
            char: GRID_CHAR,
            label: time_at_x(x)
          }
        end

        grid_lines
      end

      # Generate trigger indicator data
      def generate_trigger_data
        return nil unless @trigger_enabled && @trigger_position.positive?

        {
          position: @trigger_position,
          level: @trigger_level,
          char: TRIGGER_CHAR,
          y_position: sample_to_y_coordinate(@trigger_level),
          last_trigger_time: @last_trigger_time,
          history: @trigger_history.dup
        }
      end

      # Calculate display parameters
      def calculate_display_parameters
        @center_y = @height / 2
        @amplitude_range = @height / 2
        @time_range = @width * @time_scale
      end

      # Helper methods for grid labels
      def amplitude_at_y(y)
        amplitude = (@center_y - y).to_f / @amplitude_range
        "#{(amplitude * @amplitude_scale).round(2)}"
      end

      def time_at_x(x)
        time_ms = (x.to_f / @width) * (@time_range * 1000 / 44_100) # Assume 44.1kHz
        "#{time_ms.round(1)}ms"
      end

      # Configuration methods

      def set_channels(new_channels)
        @channels = validate_channels(new_channels)
        initialize_visualizer
      end

      def set_style(new_style)
        @style = validate_style(new_style)
      end

      def set_scaling(amplitude: nil, time: nil)
        @amplitude_scale = validate_positive_number(amplitude, "Amplitude scale") if amplitude
        @time_scale = validate_positive_number(time, "Time scale") if time
        initialize_visualizer if time # Reinitialize buffers if time scale changed
      end

      def set_trigger(enabled: nil, level: nil)
        @trigger_enabled = enabled unless enabled.nil?
        @trigger_level = validate_range(level, -1.0, 1.0, "Trigger level") if level
      end

      def toggle_center_line
        @center_line = !@center_line
      end

      def toggle_grid
        @grid_enabled = !@grid_enabled
      end

      # Validation methods

      def validate_channels(channels)
        valid_channels = %i[mono stereo left right]
        raise ArgumentError, "Channels must be one of: #{valid_channels.join(", ")}" unless valid_channels.include?(channels)

        channels
      end

      def validate_style(style)
        valid_styles = %i[line filled dots bars]
        raise ArgumentError, "Style must be one of: #{valid_styles.join(", ")}" unless valid_styles.include?(style)

        style
      end

      # Utility methods

      # Get current waveform statistics
      def waveform_statistics
        return {} if @sample_buffer.empty?

        {
          sample_count: @sample_buffer.length,
          peak_amplitude: @sample_buffer.map(&:abs).max,
          rms_amplitude: Math.sqrt(@sample_buffer.map { |s| s * s }.sum / @sample_buffer.length),
          zero_crossings: count_zero_crossings,
          trigger_count: @trigger_history.length,
          last_trigger: @last_trigger_time
        }
      end

      # Count zero crossings in the current buffer
      def count_zero_crossings
        crossings = 0
        (1...@sample_buffer.length).each do |i|
          crossings += 1 if (@sample_buffer[i] >= 0) != (@sample_buffer[i - 1] >= 0)
        end
        crossings
      end

      # Reset trigger history
      def reset_trigger
        @trigger_history.clear
        @trigger_position = 0
        @last_trigger_time = 0.0
      end
    end
  end
end
