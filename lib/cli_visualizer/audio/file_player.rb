# frozen_string_literal: true

require "open3"

module CliVisualizer
  module Audio
    # File-based audio player for MP3, WAV, and FLAC formats
    # Uses system tools (ffmpeg/sox) for decoding and provides audio data via callbacks
    # rubocop:disable Metrics/ClassLength
    class FilePlayer < Capture
      # Supported audio file formats
      SUPPORTED_FORMATS = %w[.mp3 .wav .flac .m4a .aac .ogg].freeze

      attr_reader :file_path, :position, :duration

      def initialize(file_path:, **options)
        super(**options)
        @file_path = file_path
        @position = 0.0
        @duration = nil
        @thread = nil
        @stop_requested = false
        @paused = false
        @decoder_command = nil

        validate_file!
        detect_duration
      end

      # Start playing the audio file
      # rubocop:disable Metrics/MethodLength
      def start
        return false if running? || error?

        self.status = STATUS_STARTING

        begin
          @stop_requested = false
          @paused = false
          @thread = Thread.new { decode_and_stream }
          self.status = STATUS_RUNNING
          true
        rescue StandardError => e
          self.error = "Failed to start playback: #{e.message}"
          false
        end
      end
      # rubocop:enable Metrics/MethodLength

      # Stop audio playback
      def stop
        return false if stopped?

        self.status = STATUS_STOPPING
        @stop_requested = true

        if @thread&.alive?
          @thread.join(1.0) # Wait up to 1 second
          @thread.kill if @thread&.alive? # Force kill if still running
        end

        @position = 0.0
        self.status = STATUS_STOPPED
        true
      end

      # Pause audio playback
      def pause
        return false unless running?

        @paused = true
        true
      end

      # Resume audio playback
      def resume
        return false unless running?

        @paused = false
        true
      end

      # Check if playback is paused
      def paused?
        @paused
      end

      # Get current playback position in seconds
      def position_seconds
        @position
      end

      # Get total duration in seconds
      def duration_seconds
        @duration
      end

      # Seek to a specific position (in seconds)
      def seek(position)
        return false unless @duration && position >= 0 && position <= @duration

        # For now, restart from beginning and skip to position
        # TODO: Implement true seeking for better performance
        was_running = running?
        stop if was_running
        @position = position
        start if was_running
      end

      # Get file information
      def device_info
        {
          name: "File Player: #{File.basename(@file_path)}",
          file_path: @file_path,
          format: File.extname(@file_path).downcase,
          sample_rate: @sample_rate,
          channels: @channels,
          sample_size: @sample_size,
          duration: @duration,
          position: @position
        }
      end

      # Get available decoders on the system
      def self.available_decoders
        decoders = []
        decoders << :ffmpeg if system("which ffmpeg > /dev/null 2>&1")
        decoders << :sox if system("which sox > /dev/null 2>&1")
        decoders
      end

      # Check if a file format is supported
      def self.supported_format?(file_path)
        SUPPORTED_FORMATS.include?(File.extname(file_path).downcase)
      end

      private

      # Validate that the file exists and is supported
      def validate_file!
        raise ArgumentError, "File does not exist: #{@file_path}" unless File.exist?(@file_path)

        unless self.class.supported_format?(@file_path)
          ext = File.extname(@file_path)
          raise ArgumentError, "Unsupported format: #{ext}. Supported: #{SUPPORTED_FORMATS.join(", ")}"
        end

        return if self.class.available_decoders.any?

        raise "No audio decoders found. Please install ffmpeg or sox."
      end

      # Detect audio file duration using ffprobe or soxi
      def detect_duration
        if system("which ffprobe > /dev/null 2>&1")
          @duration = detect_duration_ffprobe
        elsif system("which soxi > /dev/null 2>&1")
          @duration = detect_duration_soxi
        end
      end

      # Get duration using ffprobe
      def detect_duration_ffprobe
        cmd = ["ffprobe", "-v", "quiet", "-print_format", "csv=p=0",
               "-show_entries", "format=duration", @file_path]

        stdout, _stderr, status = Open3.capture3(*cmd)
        return nil unless status.success?

        duration = stdout.strip.to_f
        duration.positive? ? duration : nil
      rescue StandardError
        nil
      end

      # Get duration using soxi
      def detect_duration_soxi
        stdout, _stderr, status = Open3.capture3("soxi", "-D", @file_path)
        return nil unless status.success?

        duration = stdout.strip.to_f
        duration.positive? ? duration : nil
      rescue StandardError
        nil
      end

      # Main decoding and streaming loop
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def decode_and_stream
        decoder_cmd = build_decoder_command

        Open3.popen3(*decoder_cmd) do |stdin, stdout, _stderr, wait_thr|
          stdin.close

          # Read and process audio data in chunks
          buffer_size_bytes = @buffer_size * @channels * (@sample_size / 8)

          loop do
            break if @stop_requested

            if @paused
              sleep(0.01)
              next
            end

            begin
              chunk = stdout.read(buffer_size_bytes)
              break if chunk.nil? || chunk.empty?

              # Convert raw PCM data to sample array
              samples = convert_pcm_to_samples(chunk)
              next if samples.empty?

              # Update position based on samples processed
              samples_per_channel = samples.length / @channels
              @position += samples_per_channel.to_f / @sample_rate

              # Notify callbacks with audio data
              notify_audio_data(samples)
            rescue StandardError => e
              self.error = "Decoding error: #{e.message}"
              break
            end
          end

          # Wait for process to complete
          wait_thr.value
        end
      rescue StandardError => e
        self.error = "Playback error: #{e.message}"
      ensure
        self.status = STATUS_STOPPED unless error?
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      # Build the appropriate decoder command
      def build_decoder_command
        if system("which ffmpeg > /dev/null 2>&1")
          build_ffmpeg_command
        elsif system("which sox > /dev/null 2>&1")
          build_sox_command
        else
          raise "No supported decoder available"
        end
      end

      # Build ffmpeg command for decoding
      def build_ffmpeg_command
        cmd = ["ffmpeg", "-i", @file_path]

        # Add seek if position is set
        cmd += ["-ss", @position.to_s] if @position.positive?

        # Output format options
        cmd += [
          "-f", "s16le",                    # 16-bit little-endian PCM
          "-ar", @sample_rate.to_s,         # Sample rate
          "-ac", @channels.to_s,            # Channel count
          "-"                               # Output to stdout
        ]

        cmd
      end

      # Build sox command for decoding
      # rubocop:disable Metrics/MethodLength
      def build_sox_command
        cmd = ["sox", @file_path]

        # Output format options
        cmd += [
          "-t", "raw",                      # Raw PCM output
          "-e", "signed-integer",           # Signed integer samples
          "-b", @sample_size.to_s,          # Bit depth
          "-r", @sample_rate.to_s,          # Sample rate
          "-c", @channels.to_s,             # Channel count
          "-"                               # Output to stdout
        ]

        # Add trim if position is set
        cmd += ["trim", @position.to_s] if @position.positive?

        cmd
      end
      # rubocop:enable Metrics/MethodLength

      # Convert raw PCM bytes to sample array
      def convert_pcm_to_samples(pcm_data)
        # For 16-bit little-endian PCM
        samples = pcm_data.unpack("s<*") # signed 16-bit little-endian

        # Convert to float range [-1.0, 1.0]
        samples.map { |sample| sample / 32_768.0 }
      rescue StandardError
        []
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
