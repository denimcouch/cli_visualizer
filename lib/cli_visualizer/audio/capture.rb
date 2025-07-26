# frozen_string_literal: true

module CliVisualizer
  module Audio
    # Abstract base class for all audio capture implementations
    # Defines the common interface for system audio capture and file playback
    class Capture
      # Audio format configuration
      SAMPLE_RATE = 44_100    # Standard CD quality
      CHANNELS = 2            # Stereo
      SAMPLE_SIZE = 16        # 16-bit samples
      BUFFER_SIZE = 1024      # Samples per buffer

      attr_reader :sample_rate, :channels, :sample_size, :buffer_size, :status, :error_message

      # Status constants
      STATUS_STOPPED = :stopped
      STATUS_STARTING = :starting
      STATUS_RUNNING = :running
      STATUS_STOPPING = :stopping
      STATUS_ERROR = :error

      def initialize(sample_rate: SAMPLE_RATE, channels: CHANNELS,
                     sample_size: SAMPLE_SIZE, buffer_size: BUFFER_SIZE)
        @sample_rate = sample_rate
        @channels = channels
        @sample_size = sample_size
        @buffer_size = buffer_size
        @status = STATUS_STOPPED
        @error_message = nil
        @callbacks = []
      end

      # Abstract methods that must be implemented by subclasses
      def start
        raise NotImplementedError, "#{self.class} must implement #start"
      end

      def stop
        raise NotImplementedError, "#{self.class} must implement #stop"
      end

      def pause
        raise NotImplementedError, "#{self.class} must implement #pause"
      end

      def resume
        raise NotImplementedError, "#{self.class} must implement #resume"
      end

      # Check if audio capture is currently running
      def running?
        @status == STATUS_RUNNING
      end

      # Check if audio capture is stopped
      def stopped?
        @status == STATUS_STOPPED
      end

      # Check if there's an error
      def error?
        @status == STATUS_ERROR
      end

      # Register a callback to receive audio data
      # Block will be called with audio_data (array of samples)
      def on_audio_data(&block)
        @callbacks << block if block
      end

      # Remove all audio data callbacks
      def clear_callbacks
        @callbacks.clear
      end

      # Get audio device information (to be overridden by implementations)
      def device_info
        {
          name: "Unknown Device",
          sample_rate: @sample_rate,
          channels: @channels,
          sample_size: @sample_size
        }
      end

      # Get available audio devices (to be overridden by implementations)
      def self.available_devices
        []
      end

      # Factory method to create appropriate capture instance for current platform
      def self.create(type: :system, **options)
        case type
        when :system
          create_system_capture(**options)
        when :file
          create_file_capture(**options)
        else
          raise ArgumentError, "Unknown capture type: #{type}"
        end
      end

      protected

      # Called by implementations to notify listeners of new audio data
      def notify_audio_data(audio_data)
        @callbacks.each { |callback| callback.call(audio_data) }
      rescue StandardError => e
        self.error = "Callback error: #{e.message}"
      end

      # Set the current status
      def status=(status)
        @status = status
        @error_message = nil if status != STATUS_ERROR
      end

      # Set error status with message
      def error=(message)
        @status = STATUS_ERROR
        @error_message = message
      end

      class << self
        private

        # Create system audio capture for current platform
        def create_system_capture(**options)
          case RUBY_PLATFORM
          when /darwin/
            require_relative "macos_capture"
            MacOSCapture.new(**options)
          when /linux/
            require_relative "linux_capture"
            LinuxCapture.new(**options)
          else
            raise PlatformError, "System audio capture not supported on #{RUBY_PLATFORM}"
          end
        end

        # Create file audio capture
        def create_file_capture(**options)
          require_relative "file_player"
          FilePlayer.new(**options)
        end
      end
    end
  end
end
