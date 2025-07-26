# frozen_string_literal: true

require "ffi"

module CliVisualizer
  module Audio
    # macOS-specific audio capture implementation using Core Audio APIs
    # Uses FFI to interface with AudioToolbox, CoreAudio, and AudioUnit frameworks
    class MacOSCapture < Capture
      extend FFI::Library

      # Core Audio framework bindings
      begin
        ffi_lib "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",
                "/System/Library/Frameworks/CoreAudio.framework/CoreAudio",
                "/System/Library/Frameworks/AudioUnit.framework/AudioUnit"
      rescue LoadError => e
        # In test environments or non-macOS systems, the frameworks might not be available
        # We'll handle this gracefully and allow mocking for tests
        warn "Warning: Core Audio frameworks not available: #{e.message}" if $VERBOSE
      end

      # Core Audio types and constants
      typedef :uint32, :OSStatus
      typedef :uint32, :AudioComponentInstanceID
      typedef :uint32, :AudioUnitPropertyID
      typedef :uint32, :AudioUnitScope
      typedef :uint32, :AudioUnitElement
      typedef :pointer, :AudioUnit
      typedef :pointer, :AudioComponentInstance

      # Audio Unit constants
      AU_TYPE_OUTPUT = 0x61756f75 # 'auou'
      AU_SUBTYPE_HAL_OUTPUT = 0x6168616c # 'ahal'
      AU_MANUFACTURER_APPLE = 0x6170706c # 'appl'

      # Property constants
      K_AUDIO_UNIT_PROPERTY_ENABLE_IO = 2003
      K_AUDIO_UNIT_PROPERTY_SET_RENDER_CALLBACK = 23
      K_AUDIO_UNIT_PROPERTY_STREAM_FORMAT = 8
      K_AUDIO_OUTPUT_UNIT_PROPERTY_CURRENT_DEVICE = 2000
      K_AUDIO_OUTPUT_UNIT_PROPERTY_ENABLE_IO = 2003

      # Scope constants
      K_AUDIO_UNIT_SCOPE_INPUT = 1
      K_AUDIO_UNIT_SCOPE_OUTPUT = 0

      # Error codes
      NO_ERR = 0

      # Audio format flags
      K_AUDIO_FORMAT_FLAG_IS_FLOAT = (1 << 0)
      K_AUDIO_FORMAT_FLAG_IS_BIG_ENDIAN = (1 << 1)
      K_AUDIO_FORMAT_FLAG_IS_SIGNED_INTEGER = (1 << 2)
      K_AUDIO_FORMAT_FLAG_IS_PACKED = (1 << 3)
      K_AUDIO_FORMAT_FLAG_IS_ALIGNED_HIGH = (1 << 4)
      K_AUDIO_FORMAT_FLAG_IS_NON_INTERLEAVED = (1 << 5)
      K_AUDIO_FORMAT_FLAG_IS_NON_MIXABLE = (1 << 6)

      # Audio format IDs
      K_AUDIO_FORMAT_LINEAR_PCM = 0x6c70636d # 'lpcm'

      # AudioStreamBasicDescription structure
      class AudioStreamBasicDescription < FFI::Struct
        layout :sample_rate, :double,
               :format_id, :uint32,
               :format_flags, :uint32,
               :bytes_per_packet, :uint32,
               :frames_per_packet, :uint32,
               :bytes_per_frame, :uint32,
               :channels_per_frame, :uint32,
               :bits_per_channel, :uint32,
               :reserved, :uint32
      end

      # AudioBuffer structure
      class AudioBuffer < FFI::Struct
        layout :channels, :uint32,
               :data_byte_size, :uint32,
               :data, :pointer
      end

      # AudioBufferList structure
      class AudioBufferList < FFI::Struct
        layout :number_buffers, :uint32,
               :buffers, [AudioBuffer, 1]
      end

      # AudioComponentDescription structure
      class AudioComponentDescription < FFI::Struct
        layout :component_type, :uint32,
               :component_subtype, :uint32,
               :component_manufacturer, :uint32,
               :component_flags, :uint32,
               :component_flag_mask, :uint32
      end

      # Core Audio function bindings
      begin
        attach_function :AudioComponentFindNext, %i[pointer pointer], :pointer
        attach_function :AudioComponentInstanceNew, %i[pointer pointer], :OSStatus
        attach_function :AudioComponentInstanceDispose, [:pointer], :OSStatus
        attach_function :AudioUnitInitialize, [:pointer], :OSStatus
        attach_function :AudioUnitUninitialize, [:pointer], :OSStatus
        attach_function :AudioUnitSetProperty, %i[pointer AudioUnitPropertyID AudioUnitScope
                                                  AudioUnitElement pointer uint32], :OSStatus
        attach_function :AudioUnitGetProperty, %i[pointer AudioUnitPropertyID AudioUnitScope
                                                  AudioUnitElement pointer pointer], :OSStatus
        attach_function :AudioOutputUnitStart, [:pointer], :OSStatus
        attach_function :AudioOutputUnitStop, [:pointer], :OSStatus
      rescue FFI::NotFoundError => e
        # Functions not available - likely in test environment or non-macOS system
        warn "Warning: Core Audio functions not available: #{e.message}" if $VERBOSE
      end

      def initialize(**options)
        super
        @audio_unit = nil
        @capture_thread = nil
        @render_callback = nil
        @buffer_list = nil
        setup_audio_format
      end

      def start
        return false if running?

        begin
          self.status = STATUS_STARTING
          setup_audio_unit
          setup_render_callback
          configure_audio_unit

          result = AudioOutputUnitStart(@audio_unit)
          if result != NO_ERR
            self.error = "Failed to start audio unit: #{result}"
            cleanup_audio_unit
            return false
          end

          self.status = STATUS_RUNNING
          true
        rescue StandardError => e
          self.error = "Failed to start audio capture: #{e.message}"
          cleanup_audio_unit
          false
        end
      end

      def stop
        return true if stopped?

        begin
          self.status = STATUS_STOPPING

          if @audio_unit
            AudioOutputUnitStop(@audio_unit)
            cleanup_audio_unit
          end

          self.status = STATUS_STOPPED
          true
        rescue StandardError => e
          self.error = "Failed to stop audio capture: #{e.message}"
          false
        end
      end

      def pause
        # For simplicity, pause is implemented as stop on macOS
        stop
      end

      def resume
        # For simplicity, resume is implemented as start on macOS
        start
      end

      def device_info
        {
          name: "macOS System Audio",
          sample_rate: @sample_rate,
          channels: @channels,
          sample_size: @sample_size,
          platform: "macOS",
          framework: "Core Audio"
        }
      end

      def self.available_devices
        # For now, return default system audio device
        # In a full implementation, this would enumerate all audio devices
        [
          {
            id: "default",
            name: "System Audio",
            type: "output",
            sample_rate: 44_100,
            channels: 2
          }
        ]
      end

      private

      def setup_audio_format
        @audio_format = AudioStreamBasicDescription.new
        @audio_format[:sample_rate] = @sample_rate.to_f
        @audio_format[:format_id] = K_AUDIO_FORMAT_LINEAR_PCM
        @audio_format[:format_flags] = K_AUDIO_FORMAT_FLAG_IS_SIGNED_INTEGER | K_AUDIO_FORMAT_FLAG_IS_PACKED
        @audio_format[:bytes_per_packet] = @channels * (@sample_size / 8)
        @audio_format[:frames_per_packet] = 1
        @audio_format[:bytes_per_frame] = @channels * (@sample_size / 8)
        @audio_format[:channels_per_frame] = @channels
        @audio_format[:bits_per_channel] = @sample_size
        @audio_format[:reserved] = 0
      end

      def setup_audio_unit
        # Create component description for HAL output unit
        desc = AudioComponentDescription.new
        desc[:component_type] = AU_TYPE_OUTPUT
        desc[:component_subtype] = AU_SUBTYPE_HAL_OUTPUT
        desc[:component_manufacturer] = AU_MANUFACTURER_APPLE
        desc[:component_flags] = 0
        desc[:component_flag_mask] = 0

        # Find the component
        component = AudioComponentFindNext(nil, desc)
        raise AudioError, "Could not find HAL output audio component" if component.null?

        # Create audio unit instance
        audio_unit_ptr = FFI::MemoryPointer.new(:pointer)
        result = AudioComponentInstanceNew(component, audio_unit_ptr)
        raise AudioError, "Failed to create audio unit: #{result}" if result != NO_ERR

        @audio_unit = audio_unit_ptr.read_pointer
      end

      def setup_render_callback
        # Create render callback that will be called for audio data
        @render_callback = FFI::Function.new(:OSStatus,
                                             %i[pointer pointer pointer uint32 uint32
                                                pointer]) do |ref_con, action_flags, time_stamp, bus_number, frame_count, data|
          handle_audio_callback(ref_con, action_flags, time_stamp, bus_number, frame_count, data)
        end

        # Create callback struct
        callback_struct = FFI::MemoryPointer.new(:pointer, 2)
        callback_struct.put_pointer(0, @render_callback)
        callback_struct.put_pointer(FFI::Pointer::SIZE, nil) # refCon - not used

        # Set the render callback
        result = AudioUnitSetProperty(@audio_unit,
                                      K_AUDIO_UNIT_PROPERTY_SET_RENDER_CALLBACK,
                                      K_AUDIO_UNIT_SCOPE_INPUT,
                                      0,
                                      callback_struct,
                                      callback_struct.size)
        raise AudioError, "Failed to set render callback: #{result}" if result != NO_ERR
      end

      def configure_audio_unit
        # Enable input on the audio unit
        enable_io = FFI::MemoryPointer.new(:uint32)
        enable_io.write_uint32(1)
        result = AudioUnitSetProperty(@audio_unit,
                                      K_AUDIO_UNIT_PROPERTY_ENABLE_IO,
                                      K_AUDIO_UNIT_SCOPE_INPUT,
                                      1,
                                      enable_io,
                                      4)
        raise AudioError, "Failed to enable input: #{result}" if result != NO_ERR

        # Set the audio format
        result = AudioUnitSetProperty(@audio_unit,
                                      K_AUDIO_UNIT_PROPERTY_STREAM_FORMAT,
                                      K_AUDIO_UNIT_SCOPE_INPUT,
                                      1,
                                      @audio_format,
                                      @audio_format.size)
        raise AudioError, "Failed to set stream format: #{result}" if result != NO_ERR

        # Initialize the audio unit
        result = AudioUnitInitialize(@audio_unit)
        raise AudioError, "Failed to initialize audio unit: #{result}" if result != NO_ERR
      end

      # rubocop:disable Metrics/AbcSize
      def handle_audio_callback(_ref_con, _action_flags, _time_stamp, _bus_number, frame_count, _data)
        return NO_ERR unless running?

        begin
          # Allocate buffer list if needed
          unless @buffer_list
            @buffer_list = AudioBufferList.new
            @buffer_list[:number_buffers] = 1
            @buffer_list[:buffers][0][:channels] = @channels
            @buffer_list[:buffers][0][:data_byte_size] = frame_count * @channels * (@sample_size / 8)
            @buffer_list[:buffers][0][:data] = FFI::MemoryPointer.new(:int16, frame_count * @channels)
          end

          # Update buffer size for this callback
          buffer_size = frame_count * @channels * (@sample_size / 8)
          @buffer_list[:buffers][0][:data_byte_size] = buffer_size

          # Read audio data (this is a simplified approach)
          # In a real implementation, you'd need to handle the actual audio input routing

          # For now, generate some sample data to test the pipeline
          # In reality, this would be replaced with actual Core Audio input capture
          audio_data = generate_test_audio_data(frame_count)

          # Notify listeners
          notify_audio_data(audio_data) if audio_data && !audio_data.empty?

          NO_ERR
        rescue StandardError => e
          self.error = "Audio callback error: #{e.message}"
          -1 # Return error code
        end
      end
      # rubocop:enable Metrics/AbcSize

      # Temporary method to generate test audio data
      # In a real implementation, this would be replaced with actual Core Audio capture
      def generate_test_audio_data(frame_count)
        # Generate a simple sine wave for testing
        @phase ||= 0.0
        frequency = 440.0 # A4 note
        amplitude = 0.1 # Low amplitude for testing

        audio_data = []
        frame_count.times do |_i|
          sample = (amplitude * Math.sin(2 * Math::PI * frequency * @phase / @sample_rate) * 32_767).to_i
          @channels.times { audio_data << sample }
          @phase += 1
          @phase = 0 if @phase >= @sample_rate
        end

        audio_data
      end

      def cleanup_audio_unit
        return unless @audio_unit

        begin
          AudioUnitUninitialize(@audio_unit)
          AudioComponentInstanceDispose(@audio_unit)
        rescue StandardError => e
          # Log error but don't raise - cleanup should be resilient
          warn "Error during audio unit cleanup: #{e.message}"
        ensure
          @audio_unit = nil
          @buffer_list = nil
          @render_callback = nil
        end
      end
    end
  end
end
