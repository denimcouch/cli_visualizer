# frozen_string_literal: true

module CliVisualizer
  module Visualizer
    # Base class for all audio visualization modes
    # Provides common interface and shared functionality for spectrum, waveform, and abstract visualizers
    class Base
      # Visualization states
      STATE_STOPPED = :stopped
      STATE_RUNNING = :running
      STATE_PAUSED = :paused
      STATE_ERROR = :error

      # Common configuration defaults
      DEFAULT_WIDTH = 80
      DEFAULT_HEIGHT = 20
      DEFAULT_REFRESH_RATE = 30 # FPS
      DEFAULT_SMOOTHING = 0.8
      DEFAULT_SCALING = :linear

      attr_reader :width, :height, :refresh_rate, :smoothing, :scaling, :state, :error_message, :frame_count, :total_frames,
                  :name, :description

      def initialize(
        width: DEFAULT_WIDTH,
        height: DEFAULT_HEIGHT,
        refresh_rate: DEFAULT_REFRESH_RATE,
        smoothing: DEFAULT_SMOOTHING,
        scaling: DEFAULT_SCALING,
        name: nil,
        description: nil
      )
        # Display configuration
        @width = validate_positive_integer(width, "Width")
        @height = validate_positive_integer(height, "Height")
        @refresh_rate = validate_positive_number(refresh_rate, "Refresh rate")
        @smoothing = validate_range(smoothing, 0.0, 1.0, "Smoothing")
        @scaling = validate_scaling(scaling)

        # Metadata
        @name = name || self.class.name.split("::").last
        @description = description || "Audio visualization"

        # State management
        @state = STATE_STOPPED
        @error_message = nil

        # Frame tracking
        @frame_count = 0
        @total_frames = 0
        @last_frame_time = nil
        @frame_start_time = nil

        # Performance tracking
        @render_times = []
        @dropped_frames = 0

        # Audio data buffers
        @audio_history = []
        @frequency_history = []
        @max_history_size = 100

        # Callbacks
        @frame_callbacks = []
        @state_change_callbacks = []

        # Thread safety
        @mutex = Mutex.new

        # Subclass initialization
        initialize_visualizer
      end

      # Lifecycle methods - implemented by subclasses

      # Initialize visualizer-specific settings
      def initialize_visualizer
        # Override in subclasses
      end

      # Start the visualization
      def start
        @mutex.synchronize do
          return false if @state == STATE_RUNNING
          return false if @state == STATE_ERROR

          @state = STATE_RUNNING
          @frame_start_time = Time.now
          @error_message = nil

          notify_state_change(STATE_RUNNING)
          true
        end
      end

      # Stop the visualization
      def stop
        @mutex.synchronize do
          return true if @state == STATE_STOPPED

          @state = STATE_STOPPED
          @error_message = nil

          notify_state_change(STATE_STOPPED)
          true
        end
      end

      # Pause the visualization
      def pause
        @mutex.synchronize do
          return false unless @state == STATE_RUNNING

          @state = STATE_PAUSED
          notify_state_change(STATE_PAUSED)
          true
        end
      end

      # Resume the visualization
      def resume
        @mutex.synchronize do
          return false unless @state == STATE_PAUSED

          @state = STATE_RUNNING
          notify_state_change(STATE_RUNNING)
          true
        end
      end

      # Audio data processing

      # Process audio samples - called for time-domain data
      def process_audio_samples(samples)
        return unless running?
        return if samples.empty?

        @mutex.synchronize do
          # Store in history for trend analysis
          @audio_history << samples.dup
          @audio_history.shift if @audio_history.length > @max_history_size

          # Let subclass process the audio data
          process_audio_data(samples)
        end
      rescue StandardError => e
        handle_error("Audio processing error: #{e.message}")
      end

      # Process frequency data - called for frequency-domain data
      def process_frequency_data(frequency_data)
        return unless running?
        return if frequency_data.empty?

        @mutex.synchronize do
          # Store in history for trend analysis
          @frequency_history << frequency_data.dup
          @frequency_history.shift if @frequency_history.length > @max_history_size

          # Let subclass process the frequency data
          process_frequency_analysis(frequency_data)
        end
      rescue StandardError => e
        handle_error("Frequency processing error: #{e.message}")
      end

      # Rendering

      # Render a frame - main entry point
      def render_frame
        return nil unless running?

        start_time = Time.now

        @mutex.synchronize do
          # Generate frame content
          frame_data = generate_frame_data

          # Track frame timing
          @frame_count += 1
          @total_frames += 1
          @last_frame_time = start_time

          # Track performance
          render_time = Time.now - start_time
          @render_times << render_time
          @render_times.shift if @render_times.length > 100

          # Notify frame callbacks
          notify_frame_callbacks(frame_data, render_time)

          frame_data
        rescue StandardError => e
          handle_error("Rendering error: #{e.message}")
          nil
        end
      end

      # Configuration

      # Update display size
      def resize(new_width, new_height)
        @mutex.synchronize do
          @width = validate_positive_integer(new_width, "Width")
          @height = validate_positive_integer(new_height, "Height")

          # Notify subclass of size change
          handle_resize(@width, @height)
        end
      end

      # Update refresh rate
      def set_refresh_rate(new_rate)
        @refresh_rate = validate_positive_number(new_rate, "Refresh rate")
      end

      # Update smoothing factor
      def set_smoothing(new_smoothing)
        @smoothing = validate_range(new_smoothing, 0.0, 1.0, "Smoothing")
      end

      # Update scaling mode
      def set_scaling(new_scaling)
        @scaling = validate_scaling(new_scaling)
      end

      # Statistics and monitoring

      # Get current performance statistics
      def statistics
        @mutex.synchronize do
          {
            name: @name,
            state: @state,
            frame_count: @frame_count,
            total_frames: @total_frames,
            dropped_frames: @dropped_frames,
            average_render_time: calculate_average_render_time,
            current_fps: calculate_current_fps,
            uptime: calculate_uptime,
            width: @width,
            height: @height,
            refresh_rate: @refresh_rate,
            smoothing: @smoothing,
            scaling: @scaling,
            audio_history_size: @audio_history.length,
            frequency_history_size: @frequency_history.length,
            error_message: @error_message
          }
        end
      end

      # Get visualization info
      def info
        {
          name: @name,
          description: @description,
          class: self.class.name,
          supported_features: supported_features,
          default_config: default_config
        }
      end

      # State queries

      def running?
        @state == STATE_RUNNING
      end

      def stopped?
        @state == STATE_STOPPED
      end

      def paused?
        @state == STATE_PAUSED
      end

      def error?
        @state == STATE_ERROR
      end

      def healthy?
        !error? && (@render_times.empty? || calculate_average_render_time < 1.0 / @refresh_rate)
      end

      # Callback management

      def on_frame_rendered(&block)
        @frame_callbacks << block if block
      end

      def on_state_change(&block)
        @state_change_callbacks << block if block
      end

      def clear_callbacks
        @frame_callbacks.clear
        @state_change_callbacks.clear
      end

      # Reset statistics
      def reset_statistics
        @mutex.synchronize do
          @frame_count = 0
          @render_times.clear
          @dropped_frames = 0
          @frame_start_time = Time.now
        end
      end

      protected

      # Methods to be implemented by subclasses

      # Process raw audio samples (time domain)
      def process_audio_data(samples)
        # Override in subclasses that need time-domain data
      end

      # Process frequency analysis data
      def process_frequency_analysis(frequency_data)
        # Override in subclasses that need frequency-domain data
      end

      # Generate the visual frame data
      def generate_frame_data
        raise NotImplementedError, "Subclasses must implement generate_frame_data"
      end

      # Handle display size changes
      def handle_resize(new_width, new_height)
        # Override in subclasses if needed
      end

      # Get supported features for this visualizer
      def supported_features
        []
      end

      # Get default configuration
      def default_config
        {
          width: DEFAULT_WIDTH,
          height: DEFAULT_HEIGHT,
          refresh_rate: DEFAULT_REFRESH_RATE,
          smoothing: DEFAULT_SMOOTHING,
          scaling: DEFAULT_SCALING
        }
      end

      # Utility methods for subclasses

      # Apply smoothing to a value
      def smooth_value(current_value, new_value, smoothing_factor = @smoothing)
        (current_value * smoothing_factor) + (new_value * (1.0 - smoothing_factor))
      end

      # Scale value based on scaling mode
      def scale_value(value, max_value, scaling_mode = @scaling)
        case scaling_mode
        when :linear
          value / max_value
        when :logarithmic
          Math.log10(1 + (value * 9)) / Math.log10(10)
        when :square_root
          Math.sqrt(value / max_value)
        else
          value / max_value
        end
      end

      # Get audio data history for trend analysis
      def audio_history(count = 10)
        @audio_history.last(count)
      end

      # Get frequency data history for trend analysis
      def frequency_history(count = 10)
        @frequency_history.last(count)
      end

      private

      # Error handling
      def handle_error(message)
        @state = STATE_ERROR
        @error_message = message
        @dropped_frames += 1
        notify_state_change(STATE_ERROR)
      end

      # Callback notifications
      def notify_frame_callbacks(frame_data, render_time)
        @frame_callbacks.each do |callback|
          callback.call(frame_data, render_time, @frame_count)
        end
      rescue StandardError => e
        # Handle callback errors gracefully
        puts "Frame callback error: #{e.message}" if $VERBOSE
      end

      def notify_state_change_callbacks(new_state)
        @state_change_callbacks.each do |callback|
          callback.call(new_state, @state)
        end
      rescue StandardError => e
        puts "State change callback error: #{e.message}" if $VERBOSE
      end

      def notify_state_change(new_state)
        notify_state_change_callbacks(new_state)
      end

      # Performance calculations
      def calculate_average_render_time
        return 0.0 if @render_times.empty?

        @render_times.sum / @render_times.length
      end

      def calculate_current_fps
        return 0.0 if @last_frame_time.nil? || @frame_start_time.nil?

        elapsed = @last_frame_time - @frame_start_time
        return 0.0 if elapsed <= 0

        @frame_count / elapsed
      end

      def calculate_uptime
        return 0.0 if @frame_start_time.nil?

        Time.now - @frame_start_time
      end

      # Validation methods
      def validate_positive_integer(value, name)
        raise ArgumentError, "#{name} must be a positive integer" unless value.is_a?(Integer) && value.positive?

        value
      end

      def validate_positive_number(value, name)
        raise ArgumentError, "#{name} must be a positive number" unless value.is_a?(Numeric) && value.positive?

        value.to_f
      end

      def validate_range(value, min_val, max_val, name)
        unless value.is_a?(Numeric) && value >= min_val && value <= max_val
          raise ArgumentError, "#{name} must be between #{min_val} and #{max_val}"
        end

        value.to_f
      end

      def validate_scaling(scaling)
        valid_modes = %i[linear logarithmic square_root]
        raise ArgumentError, "Scaling must be one of: #{valid_modes.join(", ")}" unless valid_modes.include?(scaling)

        scaling
      end
    end
  end
end
