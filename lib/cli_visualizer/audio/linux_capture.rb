# frozen_string_literal: true

require "ffi"

module CliVisualizer
  module Audio
    # Linux-specific audio capture implementation using PulseAudio and ALSA APIs
    # Uses FFI to interface with PulseAudio (preferred) and ALSA (fallback) libraries
    class LinuxCapture < Capture
      extend FFI::Library

      # Try to load PulseAudio and ALSA libraries
      @libraries_loaded = false
      begin
        ffi_lib "pulse-simple", "pulse", "asound"
        @libraries_loaded = true
      rescue LoadError => e
        # In test environments or systems without audio libraries
        warn "Warning: Linux audio libraries not available: #{e.message}" if $VERBOSE
      end

      class << self
        attr_reader :libraries_loaded
      end

      # PulseAudio constants
      PA_SAMPLE_U8 = 0
      PA_SAMPLE_ALAW = 1
      PA_SAMPLE_ULAW = 2
      PA_SAMPLE_S16LE = 3
      PA_SAMPLE_S16BE = 4
      PA_SAMPLE_FLOAT32LE = 5
      PA_SAMPLE_FLOAT32BE = 6
      PA_SAMPLE_S32LE = 7
      PA_SAMPLE_S32BE = 8
      PA_SAMPLE_S24LE = 9
      PA_SAMPLE_S24BE = 10
      PA_SAMPLE_S24_32LE = 11
      PA_SAMPLE_S24_32BE = 12

      PA_STREAM_RECORD = 2
      PA_STREAM_PLAYBACK = 1

      # ALSA constants
      SND_PCM_STREAM_PLAYBACK = 0
      SND_PCM_STREAM_CAPTURE = 1
      SND_PCM_ACCESS_RW_INTERLEAVED = 3
      SND_PCM_FORMAT_S16_LE = 2
      SND_PCM_FORMAT_S24_LE = 6
      SND_PCM_FORMAT_S32_LE = 10

      # PulseAudio structures
      class PaSampleSpec < FFI::Struct
        layout :format, :int,
               :rate, :uint32,
               :channels, :uint8
      end

      # PulseAudio buffer attributes structure for configuring audio buffering
      class PaBufferAttr < FFI::Struct
        layout :maxlength, :uint32,
               :tlength, :uint32,
               :prebuf, :uint32,
               :minreq, :uint32,
               :fragsize, :uint32
      end

      # ALSA type definitions
      typedef :pointer, :snd_pcm_t
      typedef :int, :snd_pcm_stream_t
      typedef :int, :snd_pcm_access_t
      typedef :int, :snd_pcm_format_t
      typedef :uint, :snd_pcm_uframes_t

      # PulseAudio function bindings
      if @libraries_loaded
        begin
          attach_function :pa_simple_new, %i[string string int string string
                                             pointer pointer pointer pointer], :pointer
          attach_function :pa_simple_free, [:pointer], :void
          attach_function :pa_simple_read, %i[pointer pointer size_t pointer], :int
          attach_function :pa_simple_write, %i[pointer pointer size_t pointer], :int
          attach_function :pa_simple_drain, %i[pointer pointer], :int
          attach_function :pa_strerror, [:int], :string
        rescue FFI::NotFoundError => e
          warn "Warning: PulseAudio functions not available: #{e.message}" if $VERBOSE
        end

        # ALSA function bindings
        begin
          attach_function :snd_pcm_open, %i[pointer string snd_pcm_stream_t int], :int
          attach_function :snd_pcm_close, [:snd_pcm_t], :int
          attach_function :snd_pcm_set_params, %i[snd_pcm_t snd_pcm_format_t snd_pcm_access_t
                                                  uint uint int uint], :int
          attach_function :snd_pcm_readi, %i[snd_pcm_t pointer snd_pcm_uframes_t], :long
          attach_function :snd_pcm_writei, %i[snd_pcm_t pointer snd_pcm_uframes_t], :long
          attach_function :snd_pcm_prepare, [:snd_pcm_t], :int
          attach_function :snd_pcm_drop, [:snd_pcm_t], :int
          attach_function :snd_strerror, [:int], :string
        rescue FFI::NotFoundError => e
          warn "Warning: ALSA functions not available: #{e.message}" if $VERBOSE
        end
      end

      def initialize(**options)
        super
        @audio_system = nil # :pulseaudio or :alsa
        @pa_simple = nil
        @alsa_pcm = nil
        @capture_thread = nil
        @running = false
        detect_audio_system
      end

      def start
        return false if running?

        begin
          self.status = STATUS_STARTING

          case @audio_system
          when :pulseaudio
            start_pulseaudio
          when :alsa
            start_alsa
          else
            self.error = "No supported audio system available (PulseAudio or ALSA)"
            return false
          end

          @running = true
          start_capture_thread
          self.status = STATUS_RUNNING
          true
        rescue StandardError => e
          self.error = "Failed to start Linux audio capture: #{e.message}"
          cleanup_audio
          false
        end
      end

      def stop
        return true if stopped?

        begin
          self.status = STATUS_STOPPING
          @running = false

          @capture_thread&.join(1.0) # Wait up to 1 second for thread to finish
          cleanup_audio

          self.status = STATUS_STOPPED
          true
        rescue StandardError => e
          self.error = "Failed to stop Linux audio capture: #{e.message}"
          false
        end
      end

      def pause
        # For simplicity, pause is implemented as stop on Linux
        stop
      end

      def resume
        # For simplicity, resume is implemented as start on Linux
        start
      end

      def device_info
        {
          name: "Linux #{@audio_system&.to_s&.capitalize || "Unknown"} Audio",
          sample_rate: @sample_rate,
          channels: @channels,
          sample_size: @sample_size,
          platform: "Linux",
          audio_system: @audio_system,
          framework: case @audio_system
                     when :pulseaudio then "PulseAudio"
                     when :alsa then "ALSA"
                     end
        }
      end

      def self.available_devices
        devices = []

        # Try to detect available devices through both systems
        devices << {
          id: "default_pulse",
          name: "PulseAudio Default",
          type: "input",
          sample_rate: 44_100,
          channels: 2,
          audio_system: :pulseaudio
        }

        devices << {
          id: "default_alsa",
          name: "ALSA Default",
          type: "input",
          sample_rate: 44_100,
          channels: 2,
          audio_system: :alsa
        }

        devices
      end

      private

      def detect_audio_system
        # Try PulseAudio first (more common in modern desktop Linux)
        @audio_system = if pulseaudio_available?
                          :pulseaudio
                        elsif alsa_available?
                          :alsa
                        end
      end

      def pulseaudio_available?
        return false unless respond_to?(:pa_simple_new)

        # Try to create a simple PulseAudio connection to test availability
        sample_spec = PaSampleSpec.new
        sample_spec[:format] = PA_SAMPLE_S16LE
        sample_spec[:rate] = @sample_rate
        sample_spec[:channels] = @channels

        error_ptr = FFI::MemoryPointer.new(:int)
        pa_simple = pa_simple_new(nil, "CLI Audio Visualizer Test", PA_STREAM_RECORD,
                                  nil, "Test Connection", sample_spec, nil, nil, error_ptr)

        if pa_simple.null?
          false
        else
          pa_simple_free(pa_simple)
          true
        end
      rescue StandardError
        false
      end

      def alsa_available?
        return false unless respond_to?(:snd_pcm_open)

        # Try to open ALSA device to test availability
        pcm_ptr = FFI::MemoryPointer.new(:pointer)
        result = snd_pcm_open(pcm_ptr, "default", SND_PCM_STREAM_CAPTURE, 0)

        if result.zero?
          pcm = pcm_ptr.read_pointer
          snd_pcm_close(pcm) unless pcm.null?
          true
        else
          false
        end
      rescue StandardError
        false
      end

      def start_pulseaudio
        sample_spec = PaSampleSpec.new
        sample_spec[:format] = case @sample_size
                               when 8 then PA_SAMPLE_U8
                               when 16 then PA_SAMPLE_S16LE
                               when 24 then PA_SAMPLE_S24LE
                               when 32 then PA_SAMPLE_S32LE
                               else PA_SAMPLE_S16LE
                               end
        sample_spec[:rate] = @sample_rate
        sample_spec[:channels] = @channels

        # Configure buffer attributes for low latency
        buffer_attr = PaBufferAttr.new
        fragment_size = @buffer_size * @channels * (@sample_size / 8)
        buffer_attr[:maxlength] = fragment_size * 4
        buffer_attr[:tlength] = fragment_size
        buffer_attr[:prebuf] = 0
        buffer_attr[:minreq] = fragment_size
        buffer_attr[:fragsize] = fragment_size

        error_ptr = FFI::MemoryPointer.new(:int)
        @pa_simple = pa_simple_new(nil, "CLI Audio Visualizer", PA_STREAM_RECORD,
                                   nil, "Audio Capture", sample_spec, nil, buffer_attr, error_ptr)

        return unless @pa_simple.null?

        error_code = error_ptr.read_int
        error_msg = pa_strerror(error_code)
        raise AudioError, "Failed to create PulseAudio stream: #{error_msg}"
      end

      def start_alsa
        pcm_ptr = FFI::MemoryPointer.new(:pointer)
        result = snd_pcm_open(pcm_ptr, "default", SND_PCM_STREAM_CAPTURE, 0)

        raise AudioError, "Failed to open ALSA device: #{snd_strerror(result)}" if result.negative?

        @alsa_pcm = pcm_ptr.read_pointer

        # Set ALSA parameters
        format = case @sample_size
                 when 16 then SND_PCM_FORMAT_S16_LE
                 when 24 then SND_PCM_FORMAT_S24_LE
                 when 32 then SND_PCM_FORMAT_S32_LE
                 else SND_PCM_FORMAT_S16_LE
                 end

        result = snd_pcm_set_params(@alsa_pcm, format, SND_PCM_ACCESS_RW_INTERLEAVED,
                                    @channels, @sample_rate, 1, 100_000) # 100ms latency

        if result.negative?
          snd_pcm_close(@alsa_pcm)
          raise AudioError, "Failed to set ALSA parameters: #{snd_strerror(result)}"
        end

        # Prepare the PCM device
        result = snd_pcm_prepare(@alsa_pcm)
        return unless result.negative?

        snd_pcm_close(@alsa_pcm)
        raise AudioError, "Failed to prepare ALSA device: #{snd_strerror(result)}"
      end

      def start_capture_thread
        @capture_thread = Thread.new do
          capture_loop
        rescue StandardError => e
          self.error = "Audio capture thread error: #{e.message}"
        end
      end

      def capture_loop
        buffer_size_bytes = @buffer_size * @channels * (@sample_size / 8)
        buffer = FFI::MemoryPointer.new(:uint8, buffer_size_bytes)

        while @running
          case @audio_system
          when :pulseaudio
            capture_pulseaudio_data(buffer, buffer_size_bytes)
          when :alsa
            capture_alsa_data(buffer)
          end
        end
      end

      def capture_pulseaudio_data(buffer, buffer_size_bytes)
        error_ptr = FFI::MemoryPointer.new(:int)
        result = pa_simple_read(@pa_simple, buffer, buffer_size_bytes, error_ptr)

        if result.negative?
          error_code = error_ptr.read_int
          self.error = "PulseAudio read error: #{pa_strerror(error_code)}"
          return
        end

        # Convert buffer to audio data and notify listeners
        audio_data = buffer_to_audio_data(buffer, @buffer_size * @channels)
        notify_audio_data(audio_data) if audio_data && !audio_data.empty?
      end

      def capture_alsa_data(buffer)
        frames_read = snd_pcm_readi(@alsa_pcm, buffer, @buffer_size)

        if frames_read.negative?
          self.error = "ALSA read error: #{snd_strerror(frames_read.to_i)}"
          return
        end

        # Convert buffer to audio data and notify listeners
        audio_data = buffer_to_audio_data(buffer, frames_read * @channels)
        notify_audio_data(audio_data) if audio_data && !audio_data.empty?
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Naming/VariableNumber
      def buffer_to_audio_data(buffer, sample_count)
        audio_data = []

        case @sample_size
        when 8
          sample_count.times do |i|
            sample = buffer.get_uint8(i)
            # Convert unsigned 8-bit to signed 16-bit
            audio_data << ((sample - 128) * 256)
          end
        when 16
          sample_count.times do |i|
            sample = buffer.get_int16(i * 2)
            audio_data << sample
          end
        when 24
          sample_count.times do |i|
            # 24-bit samples are stored in 3 bytes, convert to 16-bit
            byte1 = buffer.get_uint8(i * 3)
            byte2 = buffer.get_uint8((i * 3) + 1)
            byte3 = buffer.get_uint8((i * 3) + 2)
            sample_24 = (byte3 << 16) | (byte2 << 8) | byte1
            # Convert to signed and scale down to 16-bit
            sample_24 -= 0x800000 if sample_24 >= 0x800000
            audio_data << (sample_24 >> 8)
          end
        when 32
          sample_count.times do |i|
            sample_32 = buffer.get_int32(i * 4)
            # Scale down 32-bit to 16-bit
            audio_data << (sample_32 >> 16)
          end
        else
          # Fallback: treat as 16-bit
          sample_count.times do |i|
            sample = buffer.get_int16(i * 2)
            audio_data << sample
          end
        end

        audio_data
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Naming/VariableNumber

      def cleanup_audio
        if @pa_simple && !@pa_simple.null?
          begin
            pa_simple_free(@pa_simple) if respond_to?(:pa_simple_free)
          rescue StandardError => e
            warn "Error freeing PulseAudio resources: #{e.message}"
          ensure
            @pa_simple = nil
          end
        end

        if @alsa_pcm && !@alsa_pcm.null?
          begin
            snd_pcm_drop(@alsa_pcm) if respond_to?(:snd_pcm_drop)
            snd_pcm_close(@alsa_pcm) if respond_to?(:snd_pcm_close)
          rescue StandardError => e
            warn "Error freeing ALSA resources: #{e.message}"
          ensure
            @alsa_pcm = nil
          end
        end
      rescue StandardError => e
        # Log error but don't raise - cleanup should be resilient
        warn "Error during Linux audio cleanup: #{e.message}"
      end
    end
  end
end
