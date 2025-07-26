# frozen_string_literal: true

module CliVisualizer
  module Renderer
    # Visualization scaling utility for different terminal sizes
    # Provides adaptive scaling algorithms and terminal size handling
    class Scaler
      # Scaling modes
      SCALE_STRETCH = :stretch # Stretch to fit terminal
      SCALE_FIT = :fit             # Scale to fit while maintaining aspect ratio
      SCALE_FILL = :fill           # Scale to fill terminal (may crop)
      SCALE_CENTER = :center       # Center without scaling
      SCALE_ADAPTIVE = :adaptive   # Intelligent scaling based on content

      # Standard terminal sizes for reference
      TERMINAL_SIZES = {
        tiny: { width: 40, height: 12 },
        small: { width: 80, height: 24 },
        medium: { width: 120, height: 30 },
        large: { width: 160, height: 40 },
        huge: { width: 200, height: 50 }
      }.freeze

      # Minimum viable dimensions
      MIN_WIDTH = 20
      MIN_HEIGHT = 6

      attr_reader :target_width, :target_height, :scale_mode, :original_width, :original_height

      def initialize(
        target_width:,
        target_height:,
        scale_mode: SCALE_ADAPTIVE,
        original_width: nil,
        original_height: nil
      )
        @target_width = validate_dimension(target_width, MIN_WIDTH, "width")
        @target_height = validate_dimension(target_height, MIN_HEIGHT, "height")
        @scale_mode = scale_mode
        @original_width = original_width
        @original_height = original_height

        # Calculated scaling factors
        @x_scale = 1.0
        @y_scale = 1.0
        @uniform_scale = 1.0

        calculate_scaling_factors if @original_width && @original_height
      end

      # Update target dimensions (e.g., when terminal is resized)
      def update_target_size(width, height)
        @target_width = validate_dimension(width, MIN_WIDTH, "width")
        @target_height = validate_dimension(height, MIN_HEIGHT, "height")

        calculate_scaling_factors if @original_width && @original_height
      end

      # Set original dimensions
      def set_original_size(width, height)
        @original_width = validate_dimension(width, 1, "original width")
        @original_height = validate_dimension(height, 1, "original height")

        calculate_scaling_factors
      end

      # Scale a value in the X dimension
      def scale_x(value)
        (value * @x_scale).round
      end

      # Scale a value in the Y dimension
      def scale_y(value)
        (value * @y_scale).round
      end

      # Scale a coordinate pair
      def scale_point(x, y)
        [scale_x(x), scale_y(y)]
      end

      # Scale dimensions uniformly
      def scale_uniform(value)
        (value * @uniform_scale).round
      end

      # Scale array of data points to fit target size
      def scale_data_array(data, target_length = nil)
        target_length ||= @target_width
        return data if data.empty? || target_length <= 0

        case data.length <=> target_length
        when 0
          data # Same length
        when 1
          downsample_array(data, target_length)
        when -1
          upsample_array(data, target_length)
        end
      end

      # Scale 2D frame data to fit terminal
      def scale_frame(frame_lines)
        return frame_lines if frame_lines.empty?

        scaled_lines = scale_vertical(frame_lines)
        scaled_lines.map { |line| scale_horizontal(line) }
      end

      # Get optimal scaling for specific visualization type
      def optimal_scaling_for(visualization_type)
        case visualization_type
        when :spectrum
          spectrum_scaling
        when :waveform
          waveform_scaling
        when :abstract
          abstract_scaling
        else
          default_scaling
        end
      end

      # Calculate effective viewport dimensions
      def effective_dimensions
        {
          width: @target_width,
          height: @target_height,
          scale_x: @x_scale,
          scale_y: @y_scale,
          uniform_scale: @uniform_scale,
          aspect_ratio: @target_width.to_f / @target_height
        }
      end

      # Check if scaling is needed
      def scaling_needed?
        return false unless @original_width && @original_height

        @original_width != @target_width || @original_height != @target_height
      end

      # Get terminal size category
      def terminal_size_category
        total_chars = @target_width * @target_height

        case total_chars
        when 0..500 then :tiny
        when 501..2000 then :small
        when 2001..4000 then :medium
        when 4001..8000 then :large
        else :huge
        end
      end

      # Get scaling recommendations based on terminal size
      def scaling_recommendations
        category = terminal_size_category

        case category
        when :tiny
          {
            bands: 8,
            refresh_rate: 15,
            detail_level: :low,
            use_color: false,
            charset: :basic
          }
        when :small
          {
            bands: 16,
            refresh_rate: 20,
            detail_level: :medium,
            use_color: true,
            charset: :extended
          }
        when :medium, :large, :huge
          {
            bands: 32,
            refresh_rate: 30,
            detail_level: :high,
            use_color: true,
            charset: :unicode
          }
        end
      end

      # Auto-adjust visualization parameters
      def auto_adjust_parameters(base_params)
        recommendations = scaling_recommendations
        adjusted = base_params.dup

        # Apply scaling recommendations
        recommendations.each do |key, value|
          adjusted[key] = value if adjusted.key?(key)
        end

        # Scale numeric parameters
        adjusted[:width] = @target_width if base_params[:width]

        adjusted[:height] = @target_height if base_params[:height]

        adjusted
      end

      private

      # Validate dimension value
      def validate_dimension(value, minimum, name)
        unless value.is_a?(Integer) && value >= minimum
          raise ArgumentError, "#{name} must be an integer >= #{minimum}, got #{value}"
        end

        value
      end

      # Calculate scaling factors based on mode
      def calculate_scaling_factors
        case @scale_mode
        when SCALE_STRETCH
          @x_scale = @target_width.to_f / @original_width
          @y_scale = @target_height.to_f / @original_height
          @uniform_scale = [@x_scale, @y_scale].min
        when SCALE_FIT
          scale = [@target_width.to_f / @original_width, @target_height.to_f / @original_height].min
          @x_scale = @y_scale = @uniform_scale = scale
        when SCALE_FILL
          scale = [@target_width.to_f / @original_width, @target_height.to_f / @original_height].max
          @x_scale = @y_scale = @uniform_scale = scale
        when SCALE_CENTER
          @x_scale = @y_scale = @uniform_scale = 1.0
        when SCALE_ADAPTIVE
          adaptive_scaling
        end
      end

      # Adaptive scaling algorithm
      def adaptive_scaling
        width_ratio = @target_width.to_f / @original_width
        height_ratio = @target_height.to_f / @original_height

        # Use different strategies based on aspect ratio differences
        aspect_diff = (@target_width.to_f / @target_height) / (@original_width.to_f / @original_height)

        if aspect_diff.between?(0.8, 1.2)
          # Similar aspect ratios - use uniform scaling
          @x_scale = @y_scale = @uniform_scale = [width_ratio, height_ratio].min
        else
          # Different aspect ratios - allow non-uniform scaling but limit distortion
          max_distortion = 1.5

          @x_scale = [width_ratio, height_ratio * max_distortion].min
          @y_scale = [height_ratio, width_ratio * max_distortion].min
          @uniform_scale = [@x_scale, @y_scale].min
        end
      end

      # Downsample array to smaller size
      def downsample_array(data, target_length)
        return data[0, target_length] if target_length >= data.length

        step = data.length.to_f / target_length
        downsampled = []

        target_length.times do |i|
          index = (i * step).round
          downsampled << data[index] if index < data.length
        end

        downsampled
      end

      # Upsample array to larger size
      def upsample_array(data, target_length)
        return data if target_length <= data.length

        upsampled = []
        scale = (data.length - 1).to_f / (target_length - 1)

        target_length.times do |i|
          float_index = i * scale
          index = float_index.floor
          fraction = float_index - index

          if index >= data.length - 1
            upsampled << data.last
          else
            # Linear interpolation
            value1 = data[index]
            value2 = data[index + 1]

            if value1.is_a?(Numeric) && value2.is_a?(Numeric)
              interpolated = value1 + ((value2 - value1) * fraction)
              upsampled << interpolated
            else
              upsampled << (fraction < 0.5 ? value1 : value2)
            end
          end
        end

        upsampled
      end

      # Scale lines vertically
      def scale_vertical(lines)
        return lines if lines.length == @target_height

        if lines.length > @target_height
          # Downsample lines
          step = lines.length.to_f / @target_height
          scaled = []

          @target_height.times do |i|
            index = (i * step).round
            scaled << lines[index] if index < lines.length
          end

          scaled
        else
          # Upsample lines
          scaled = []
          scale = (lines.length - 1).to_f / (@target_height - 1)

          @target_height.times do |i|
            float_index = i * scale
            index = float_index.floor

            scaled << (lines[index] || lines.last || "")
          end

          scaled
        end
      end

      # Scale line horizontally
      def scale_horizontal(line)
        return line if line.length == @target_width

        if line.length > @target_width
          # Truncate or downsample
          step = line.length.to_f / @target_width
          scaled = ""

          @target_width.times do |i|
            index = (i * step).round
            scaled += line[index] if index < line.length
          end

          scaled
        elsif line.length < @target_width / 2
          # Pad or upsample
          (line * (@target_width.to_f / line.length).ceil)[0, @target_width]

        # Repeat pattern if line is much shorter
        else
          # Pad with spaces
          line.ljust(@target_width)
        end
      end

      # Spectrum-specific scaling
      def spectrum_scaling
        # For spectrum analyzers, prefer width scaling over height
        @x_scale = @target_width.to_f / (@original_width || @target_width)
        @y_scale = @target_height.to_f / (@original_height || @target_height)
        @uniform_scale = @x_scale
      end

      # Waveform-specific scaling
      def waveform_scaling
        # For waveforms, maintain time-domain accuracy
        @x_scale = @target_width.to_f / (@original_width || @target_width)
        @y_scale = @target_height.to_f / (@original_height || @target_height)
        @uniform_scale = [@x_scale, @y_scale].min
      end

      # Abstract visualization scaling
      def abstract_scaling
        # For abstract patterns, prefer uniform scaling
        scale = [@target_width.to_f / (@original_width || @target_width),
                 @target_height.to_f / (@original_height || @target_height)].min
        @x_scale = @y_scale = @uniform_scale = scale
      end

      # Default scaling algorithm
      def default_scaling
        adaptive_scaling
      end
    end
  end
end
