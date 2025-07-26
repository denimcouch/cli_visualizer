# frozen_string_literal: true

require "io/console"

module CliVisualizer
  module Renderer
    # Terminal ASCII renderer with animation support
    # Handles terminal output, buffering, cursor control, and smooth animations
    class Terminal
      # Animation and timing constants
      DEFAULT_FRAME_RATE = 30 # FPS
      MAX_FRAME_RATE = 60
      MIN_FRAME_RATE = 5
      CLEAR_SCREEN = "\e[2J\e[H"
      CURSOR_HOME = "\e[H"
      HIDE_CURSOR = "\e[?25l"
      SHOW_CURSOR = "\e[?25h"

      # Buffer management
      DOUBLE_BUFFER = true

      attr_reader :width, :height, :frame_rate, :buffer, :last_frame_time, :frame_count

      def initialize(
        width: nil,
        height: nil,
        frame_rate: DEFAULT_FRAME_RATE,
        double_buffered: DOUBLE_BUFFER,
        output: $stdout
      )
        @output = output
        @frame_rate = validate_frame_rate(frame_rate)
        @frame_interval = 1.0 / @frame_rate
        @double_buffered = double_buffered

        # Get terminal dimensions
        detect_terminal_size
        @width = width || @terminal_width
        @height = height || @terminal_height

        # Animation state
        @running = false
        @paused = false
        @frame_count = 0
        @last_frame_time = nil
        @start_time = nil

        # Buffers for smooth rendering
        @current_buffer = Array.new(@height) { Array.new(@width, " ") }
        @previous_buffer = Array.new(@height) { Array.new(@width, " ") } if @double_buffered
        @dirty_regions = []

        # Terminal state management
        @original_state = nil
        @initialized = false
      end

      # Initialize terminal for rendering
      def initialize_terminal
        return if @initialized

        begin
          # Store original terminal state
          @original_state = {
            cursor_visible: true,
            raw_mode: false
          }

          # Set up terminal for animation
          @output.print HIDE_CURSOR
          @output.print CLEAR_SCREEN
          @output.flush

          @initialized = true
        rescue StandardError => e
          raise VisualizationError, "Failed to initialize terminal: #{e.message}"
        end
      end

      # Clean up terminal state
      def cleanup
        return unless @initialized

        begin
          @output.print SHOW_CURSOR
          @output.print "\n"
          @output.flush
        rescue StandardError
          # Ignore cleanup errors
        ensure
          @initialized = false
        end
      end

      # Start animation loop
      def start_animation
        return if @running

        initialize_terminal
        @running = true
        @paused = false
        @start_time = Time.now
        @last_frame_time = @start_time
        @frame_count = 0
      end

      # Stop animation
      def stop_animation
        @running = false
        cleanup
      end

      # Pause animation
      def pause
        @paused = true
      end

      # Resume animation
      def resume
        return unless @running

        @paused = false
        @last_frame_time = Time.now # Reset timing to avoid time jumps
      end

      # Render a frame to the terminal
      def render_frame(frame_data)
        return unless @running && !@paused

        current_time = Time.now

        # Frame rate limiting
        if @last_frame_time && (current_time - @last_frame_time) < @frame_interval
          return false # Frame skipped
        end

        begin
          # Update buffers
          update_buffer(frame_data)

          # Render to terminal
          if @double_buffered
            render_with_double_buffering
          else
            render_direct
          end

          @frame_count += 1
          @last_frame_time = current_time

          true # Frame rendered
        rescue StandardError => e
          raise VisualizationError, "Failed to render frame: #{e.message}"
        end
      end

      # Render text at specific position
      def render_text(text, x, y, style: nil)
        return if x < 0 || y < 0 || x >= @width || y >= @height

        # Apply styling if provided
        styled_text = style ? apply_style(text, style) : text

        # Truncate text to fit within bounds
        max_length = @width - x
        styled_text = styled_text[0, max_length] if styled_text.length > max_length

        # Update buffer
        styled_text.each_char.with_index do |char, offset|
          break if x + offset >= @width

          @current_buffer[y][x + offset] = char
        end

        # Mark region as dirty for double buffering
        mark_dirty_region(x, y, styled_text.length, 1) if @double_buffered
      end

      # Clear screen
      def clear_screen
        @current_buffer.each { |row| row.fill(" ") }
        @output.print CLEAR_SCREEN if @running
      end

      # Get terminal dimensions
      def terminal_size
        [@terminal_width, @terminal_height]
      end

      # Check if terminal supports color
      def color_supported?
        return @color_supported if defined?(@color_supported)

        @color_supported = begin
          # Check environment variables
          term = ENV.fetch("TERM", nil)
          return false unless term

          # Check for common color terminal types
          color_terms = %w[xterm xterm-color xterm-256color screen screen-256color tmux tmux-256color]
          color_terms.any? { |ct| term.include?(ct) } ||
            ENV["COLORTERM"] ||
            term.include?("color")
        rescue StandardError
          false
        end
      end

      # Get current frame rate (actual, calculated from timing)
      def actual_frame_rate
        return 0 if @frame_count == 0 || !@start_time

        elapsed = Time.now - @start_time
        return 0 if elapsed <= 0

        @frame_count / elapsed
      end

      # Get animation statistics
      def animation_stats
        {
          running: @running,
          paused: @paused,
          frame_count: @frame_count,
          target_fps: @frame_rate,
          actual_fps: actual_frame_rate.round(2),
          uptime: @start_time ? (Time.now - @start_time).round(2) : 0,
          buffer_size: [@width, @height]
        }
      end

      # Resize terminal buffer
      def resize(new_width, new_height)
        @width = new_width
        @height = new_height

        # Recreate buffers
        @current_buffer = Array.new(@height) { Array.new(@width, " ") }
        @previous_buffer = Array.new(@height) { Array.new(@width, " ") } if @double_buffered
        @dirty_regions.clear

        # Clear terminal
        @output.print CLEAR_SCREEN if @running
      end

      private

      # Validate frame rate
      def validate_frame_rate(rate)
        return DEFAULT_FRAME_RATE unless rate.is_a?(Numeric)

        [[rate, MIN_FRAME_RATE].max, MAX_FRAME_RATE].min
      end

      # Detect terminal size
      def detect_terminal_size
        if @output.respond_to?(:winsize)
          rows, cols = @output.winsize
          @terminal_height = rows > 0 ? rows : 24
          @terminal_width = cols > 0 ? cols : 80
        else
          @terminal_height = 24
          @terminal_width = 80
        end
      rescue StandardError
        @terminal_height = 24
        @terminal_width = 80
      end

      # Update internal buffer with frame data
      def update_buffer(frame_data)
        case frame_data
        when String
          # Single string - split into lines
          lines = frame_data.split("\n")
          lines.each_with_index do |line, y|
            next if y >= @height

            line.each_char.with_index do |char, x|
              next if x >= @width

              @current_buffer[y][x] = char
            end
          end
        when Array
          # Array of strings or 2D array
          frame_data.each_with_index do |row, y|
            next if y >= @height

            case row
            when String
              row.each_char.with_index do |char, x|
                next if x >= @width

                @current_buffer[y][x] = char
              end
            when Array
              row.each_with_index do |char, x|
                next if x >= @width

                @current_buffer[y][x] = char.to_s
              end
            end
          end
        else
          raise ArgumentError, "Invalid frame data format: #{frame_data.class}"
        end
      end

      # Render using double buffering (only update changed regions)
      def render_with_double_buffering
        changes_made = false

        @current_buffer.each_with_index do |row, y|
          row.each_with_index do |char, x|
            next unless @previous_buffer[y][x] != char

            # Move cursor and update character
            @output.print "\e[#{y + 1};#{x + 1}H#{char}"
            @previous_buffer[y][x] = char
            changes_made = true
          end
        end

        @output.flush if changes_made
      end

      # Direct rendering (redraw everything)
      def render_direct
        @output.print CURSOR_HOME

        @current_buffer.each_with_index do |row, y|
          @output.print row.join
          @output.print "\n" unless y == @height - 1
        end

        @output.flush
      end

      # Mark region as dirty for optimized updates
      def mark_dirty_region(x, y, width, height)
        @dirty_regions << { x: x, y: y, width: width, height: height }
      end

      # Apply text styling
      def apply_style(text, style)
        return text unless color_supported?

        codes = []

        # Text attributes
        codes << "1" if style[:bold]
        codes << "3" if style[:italic]
        codes << "4" if style[:underline]

        # Colors
        codes << "3#{style[:color]}" if style[:color]
        codes << "4#{style[:background]}" if style[:background]

        return text if codes.empty?

        "\e[#{codes.join(";")}m#{text}\e[0m"
      end
    end
  end
end
