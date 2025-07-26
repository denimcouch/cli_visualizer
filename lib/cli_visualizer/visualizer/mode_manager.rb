# frozen_string_literal: true

require_relative "base"
require_relative "spectrum"
require_relative "waveform"
require_relative "abstract"

module CliVisualizer
  module Visualizer
    # Mode switching system between visualization types
    # Handles transitions, state management, and seamless mode changes
    class ModeManager
      # Available visualization modes
      MODES = {
        spectrum: {
          class: Spectrum,
          name: "Spectrum Analyzer",
          description: "Frequency spectrum bars (equalizer style)",
          key: "s",
          icon: "▇"
        },
        waveform: {
          class: Waveform,
          name: "Waveform",
          description: "Audio waveform visualization",
          key: "w",
          icon: "〜"
        },
        abstract: {
          class: Abstract,
          name: "Abstract",
          description: "Artistic abstract patterns",
          key: "a",
          icon: "✦"
        }
      }.freeze

      # Transition effects
      TRANSITION_NONE = :none
      TRANSITION_FADE = :fade
      TRANSITION_SLIDE = :slide
      TRANSITION_CROSSFADE = :crossfade

      # Default settings
      DEFAULT_MODE = :spectrum
      DEFAULT_TRANSITION = TRANSITION_FADE
      DEFAULT_TRANSITION_DURATION = 0.5 # seconds

      attr_reader :current_mode, :previous_mode, :available_modes, :transition_progress, :transitioning

      def initialize(
        initial_mode: DEFAULT_MODE,
        transition_type: DEFAULT_TRANSITION,
        transition_duration: DEFAULT_TRANSITION_DURATION,
        **shared_options
      )
        @shared_options = shared_options
        @transition_type = transition_type
        @transition_duration = transition_duration

        # Mode management
        @current_mode = nil
        @previous_mode = nil
        @available_modes = MODES.keys
        @visualizers = {}

        # Transition state
        @transitioning = false
        @transition_start_time = nil
        @transition_progress = 0.0
        @pending_mode = nil

        # Initialize with the starting mode
        switch_to_mode(initial_mode)
      end

      # Switch to a specific visualization mode
      def switch_to_mode(mode_name, transition: nil, duration: nil)
        mode_sym = mode_name.to_sym

        unless MODES.key?(mode_sym)
          raise ArgumentError, "Unknown visualization mode: #{mode_name}. Available: #{@available_modes.join(", ")}"
        end

        return false if mode_sym == @current_mode && !@transitioning

        # Handle transition from current mode
        if @current_mode && @transition_type != TRANSITION_NONE
          start_transition(mode_sym, transition || @transition_type, duration || @transition_duration)
        else
          switch_immediately(mode_sym)
        end

        true
      end

      # Switch to next mode in sequence
      def switch_to_next_mode
        current_index = @available_modes.index(@current_mode) || 0
        next_index = (current_index + 1) % @available_modes.length
        next_mode = @available_modes[next_index]

        switch_to_mode(next_mode)
      end

      # Switch to previous mode in sequence
      def switch_to_previous_mode
        current_index = @available_modes.index(@current_mode) || 0
        prev_index = (current_index - 1) % @available_modes.length
        prev_mode = @available_modes[prev_index]

        switch_to_mode(prev_mode)
      end

      # Get current visualizer instance
      def current_visualizer
        @visualizers[@current_mode]
      end

      # Get previous visualizer instance (during transitions)
      def previous_visualizer
        @visualizers[@previous_mode]
      end

      # Update visualization with audio data
      def update(audio_data, frequency_data)
        current_time = Time.now

        # Update transition progress
        update_transition_progress(current_time) if @transitioning

        # Update current visualizer
        current_visualizer.update(audio_data, frequency_data) if current_visualizer

        # Update previous visualizer during transition
        previous_visualizer.update(audio_data, frequency_data) if @transitioning && previous_visualizer
      end

      # Render current visualization frame
      def render_frame
        return "" unless current_visualizer

        if @transitioning && previous_visualizer
          render_transition_frame
        else
          current_visualizer.render_frame
        end
      end

      # Handle key press for mode switching
      def handle_keypress(key)
        case key.downcase
        when "n", "tab"
          switch_to_next_mode
        when "p", "shift+tab"
          switch_to_previous_mode
        else
          # Check for mode-specific keys
          MODES.each do |mode, config|
            if key.downcase == config[:key]
              switch_to_mode(mode)
              return true
            end
          end
          false
        end
      end

      # Get available modes with metadata
      def mode_list
        MODES.map do |key, config|
          {
            key: key,
            name: config[:name],
            description: config[:description],
            hotkey: config[:key],
            icon: config[:icon],
            current: key == @current_mode,
            available: true
          }
        end
      end

      # Get current mode info
      def current_mode_info
        return nil unless @current_mode

        config = MODES[@current_mode]
        {
          key: @current_mode,
          name: config[:name],
          description: config[:description],
          hotkey: config[:key],
          icon: config[:icon],
          visualizer: current_visualizer
        }
      end

      # Configure transition settings
      def configure_transitions(type: nil, duration: nil)
        @transition_type = type if type
        @transition_duration = duration if duration
      end

      # Check if transition is in progress
      def transitioning?
        @transitioning
      end

      # Force complete any pending transition
      def complete_transition
        return unless @transitioning

        switch_immediately(@pending_mode) if @pending_mode
        @transitioning = false
        @transition_progress = 0.0
        @pending_mode = nil
      end

      # Resize all visualizers
      def resize(width, height)
        @visualizers.each_value do |visualizer|
          visualizer.handle_resize(width, height) if visualizer.respond_to?(:handle_resize)
        end
      end

      # Start all visualizers
      def start
        current_visualizer&.start
      end

      # Stop all visualizers
      def stop
        @visualizers.each_value(&:stop)
      end

      # Pause current visualizer
      def pause
        current_visualizer&.pause
      end

      # Resume current visualizer
      def resume
        current_visualizer&.resume
      end

      # Get statistics for all modes
      def statistics
        {
          current_mode: @current_mode,
          available_modes: @available_modes,
          transitioning: @transitioning,
          transition_progress: @transition_progress,
          loaded_visualizers: @visualizers.keys,
          mode_stats: @visualizers.transform_values do |visualizer|
            visualizer.respond_to?(:statistics) ? visualizer.statistics : {}
          end
        }
      end

      private

      # Switch immediately without transition
      def switch_immediately(mode_sym)
        @previous_mode = @current_mode
        @current_mode = mode_sym

        # Ensure visualizer is loaded
        load_visualizer(mode_sym)

        # Stop previous visualizer
        @visualizers[@previous_mode].stop if @previous_mode && @visualizers[@previous_mode]

        # Start new visualizer
        @visualizers[@current_mode].start

        @transitioning = false
        @transition_progress = 0.0
      end

      # Start transition between modes
      def start_transition(new_mode, transition_type, duration)
        @previous_mode = @current_mode
        @pending_mode = new_mode
        @transition_type = transition_type
        @transition_duration = duration
        @transitioning = true
        @transition_start_time = Time.now
        @transition_progress = 0.0

        # Load new visualizer
        load_visualizer(new_mode)

        # Start new visualizer
        @visualizers[new_mode].start
      end

      # Update transition progress
      def update_transition_progress(current_time)
        return unless @transitioning && @transition_start_time

        elapsed = current_time - @transition_start_time
        @transition_progress = elapsed / @transition_duration

        if @transition_progress >= 1.0
          # Transition complete
          complete_transition
        end
      end

      # Render frame during transition
      def render_transition_frame
        case @transition_type
        when TRANSITION_FADE
          render_fade_transition
        when TRANSITION_SLIDE
          render_slide_transition
        when TRANSITION_CROSSFADE
          render_crossfade_transition
        else
          current_visualizer.render_frame
        end
      end

      # Render fade transition
      def render_fade_transition
        # Simple fade: gradually replace previous frame with new frame
        previous_frame = previous_visualizer.render_frame
        current_frame = @visualizers[@pending_mode].render_frame

        blend_frames(previous_frame, current_frame, @transition_progress)
      end

      # Render slide transition
      def render_slide_transition
        # Slide new frame in from the right
        previous_frame = previous_visualizer.render_frame
        current_frame = @visualizers[@pending_mode].render_frame

        slide_frames(previous_frame, current_frame, @transition_progress)
      end

      # Render crossfade transition
      def render_crossfade_transition
        # Crossfade with alpha blending
        previous_frame = previous_visualizer.render_frame
        current_frame = @visualizers[@pending_mode].render_frame

        crossfade_frames(previous_frame, current_frame, @transition_progress)
      end

      # Load visualizer instance for mode
      def load_visualizer(mode_sym)
        return if @visualizers[mode_sym]

        config = MODES[mode_sym]
        visualizer_class = config[:class]

        @visualizers[mode_sym] = visualizer_class.new(@shared_options)
      end

      # Blend two frames based on progress
      def blend_frames(frame1, frame2, progress)
        # Simple character-by-character blending
        lines1 = frame1.split("\n")
        lines2 = frame2.split("\n")

        max_lines = [lines1.length, lines2.length].max
        blended_lines = []

        max_lines.times do |i|
          line1 = lines1[i] || ""
          line2 = lines2[i] || ""

          blended_line = blend_line(line1, line2, progress)
          blended_lines << blended_line
        end

        blended_lines.join("\n")
      end

      # Slide frames horizontally
      def slide_frames(frame1, frame2, progress)
        lines1 = frame1.split("\n")
        lines2 = frame2.split("\n")

        max_lines = [lines1.length, lines2.length].max
        width = @shared_options[:width] || 80

        slide_distance = (width * progress).to_i

        slid_lines = []
        max_lines.times do |i|
          line1 = (lines1[i] || "").ljust(width)
          line2 = (lines2[i] || "").ljust(width)

          # Take characters from both lines based on slide position
          if slide_distance < width
            slid_line = line1[slide_distance..-1] + line2[0, slide_distance]
            slid_line = slid_line[0, width] if slid_line.length > width
          else
            slid_line = line2
          end

          slid_lines << slid_line
        end

        slid_lines.join("\n")
      end

      # Crossfade frames with alpha blending
      def crossfade_frames(frame1, frame2, progress)
        # For ASCII, we'll use a dithering pattern to simulate transparency
        lines1 = frame1.split("\n")
        lines2 = frame2.split("\n")

        max_lines = [lines1.length, lines2.length].max
        crossfaded_lines = []

        max_lines.times do |i|
          line1 = lines1[i] || ""
          line2 = lines2[i] || ""

          crossfaded_line = crossfade_line(line1, line2, progress, i)
          crossfaded_lines << crossfaded_line
        end

        crossfaded_lines.join("\n")
      end

      # Blend individual line
      def blend_line(line1, line2, progress)
        max_length = [line1.length, line2.length].max
        blended = ""

        max_length.times do |j|
          char1 = line1[j] || " "
          char2 = line2[j] || " "

          # Simple character selection based on progress
          blended += if progress < 0.5
                       char1
                     else
                       char2
                     end
        end

        blended
      end

      # Crossfade individual line with dithering
      def crossfade_line(line1, line2, progress, line_index)
        max_length = [line1.length, line2.length].max
        crossfaded = ""

        max_length.times do |j|
          char1 = line1[j] || " "
          char2 = line2[j] || " "

          # Use checkerboard dithering pattern
          crossfaded += if (line_index + j).even?
                          progress > 0.5 ? char2 : char1
                        else
                          progress > 0.3 ? char2 : char1
                        end
        end

        crossfaded
      end
    end
  end
end
