# frozen_string_literal: true

require_relative "capture"
require_relative "buffer_manager"

module CliVisualizer
  module Audio
    # Manages multiple audio sources and provides seamless switching between them
    # Integrates with buffer management system for real-time audio processing
    class SourceManager
      # Source types
      SOURCE_SYSTEM = :system
      SOURCE_FILE = :file
      SOURCE_NONE = :none

      # Manager states
      STATE_STOPPED = :stopped
      STATE_STARTING = :starting
      STATE_RUNNING = :running
      STATE_STOPPING = :stopping
      STATE_SWITCHING = :switching
      STATE_ERROR = :error

      attr_reader :current_source_type, :current_source, :buffer_manager, :state, :available_sources, :source_history,
                  :switch_count

      def initialize(buffer_manager: nil, **buffer_options)
        @buffer_manager = buffer_manager || BufferManager.new(**buffer_options)
        @current_source_type = SOURCE_NONE
        @current_source = nil
        @state = STATE_STOPPED
        @error_message = nil

        # Source management
        @available_sources = {}
        @source_history = []
        @switch_count = 0
        @switching_in_progress = false

        # Audio routing
        @main_buffer = nil
        @audio_callback = nil

        # Monitoring
        @stats = {
          sources_created: 0,
          successful_switches: 0,
          failed_switches: 0,
          total_runtime: 0.0,
          last_switch_time: nil
        }

        setup_main_buffer
      end

      # Create and register an audio source
      def create_source(source_id, type:, **options)
        validate_source_type(type)

        begin
          source = Capture.create(type: type, **options)
          @available_sources[source_id] = {
            type: type,
            source: source,
            options: options,
            created_at: Time.now,
            switch_count: 0
          }

          @stats[:sources_created] += 1
          source_id
        rescue StandardError => e
          raise SourceError, "Failed to create #{type} source '#{source_id}': #{e.message}"
        end
      end

      # Switch to a different audio source
      def switch_to_source(source_id, fade_duration: 0.1)
        return false if @switching_in_progress || !@available_sources.key?(source_id)

        @switching_in_progress = true
        @state = STATE_SWITCHING

        begin
          old_source = @current_source
          old_source_type = @current_source_type
          new_source_info = @available_sources[source_id]

          # Perform the switch
          success = perform_source_switch(old_source, new_source_info, fade_duration)

          if success
            @current_source = new_source_info[:source]
            @current_source_type = new_source_info[:type]
            @switch_count += 1
            @stats[:successful_switches] += 1
            @stats[:last_switch_time] = Time.now

            # Update source history
            @source_history << {
              from: old_source_type,
              to: @current_source_type,
              source_id: source_id,
              timestamp: Time.now,
              success: true
            }

            new_source_info[:switch_count] += 1
            @state = @current_source.running? ? STATE_RUNNING : STATE_STOPPED
          else
            @stats[:failed_switches] += 1
            @source_history << {
              from: old_source_type,
              to: new_source_info[:type],
              source_id: source_id,
              timestamp: Time.now,
              success: false,
              error: @error_message
            }
            @state = old_source&.running? ? STATE_RUNNING : STATE_STOPPED
          end

          success
        ensure
          @switching_in_progress = false
        end
      end

      # Start the current audio source
      def start
        return false unless @current_source && !@switching_in_progress
        return true if running?

        @state = STATE_STARTING

        if @current_source.start
          @state = STATE_RUNNING
          true
        else
          @state = STATE_ERROR
          @error_message = @current_source.error_message
          false
        end
      end

      # Stop the current audio source
      def stop
        return true if stopped?
        return false if @switching_in_progress

        @state = STATE_STOPPING

        if @current_source&.stop
          @state = STATE_STOPPED
          @main_buffer&.clear
          true
        else
          @state = STATE_ERROR
          @error_message = @current_source&.error_message
          false
        end
      end

      # Pause the current audio source
      def pause
        return false unless @current_source && running?

        @current_source.pause
      end

      # Resume the current audio source
      def resume
        return false unless @current_source

        if @current_source.resume
          @state = STATE_RUNNING if @current_source.running?
          true
        else
          false
        end
      end

      # Get current source information
      def current_source_info
        return nil unless @current_source

        source_entry = @available_sources.find { |_, info| info[:source] == @current_source }
        return nil unless source_entry

        source_id, source_info = source_entry
        {
          id: source_id,
          type: source_info[:type],
          status: @current_source.status,
          device_info: @current_source.device_info,
          created_at: source_info[:created_at],
          switch_count: source_info[:switch_count],
          running: @current_source.running?
        }
      end

      # List all available sources
      def list_sources
        @available_sources.transform_values do |info|
          {
            type: info[:type],
            status: info[:source].status,
            device_info: info[:source].device_info,
            created_at: info[:created_at],
            switch_count: info[:switch_count]
          }
        end
      end

      # Remove a source
      def remove_source(source_id)
        return false unless @available_sources.key?(source_id)
        return false if @current_source == @available_sources[source_id][:source]

        source_info = @available_sources.delete(source_id)
        source_info[:source].stop if source_info[:source].running?
        true
      end

      # Register callback for processed audio data
      def on_audio_data(&block)
        @audio_callback = block if block
      end

      # Get comprehensive statistics
      def stats
        base_stats = @stats.dup
        base_stats.merge(
          current_source: current_source_info,
          available_source_count: @available_sources.size,
          state: @state,
          switch_count: @switch_count,
          switching_in_progress: @switching_in_progress,
          buffer_stats: @buffer_manager.stats,
          main_buffer_stats: @main_buffer&.stats,
          uptime: calculate_uptime,
          error_message: @error_message
        )
      end

      # Get switching history
      def switch_history(limit: 50)
        @source_history.last(limit)
      end

      # Check manager state
      def running?
        @state == STATE_RUNNING
      end

      def stopped?
        @state == STATE_STOPPED
      end

      def switching?
        @switching_in_progress
      end

      def error?
        @state == STATE_ERROR
      end

      # Quick source switching helpers
      def switch_to_system_audio(**options)
        source_id = find_or_create_system_source(**options)
        switch_to_source(source_id)
      end

      def switch_to_file(file_path, **options)
        source_id = find_or_create_file_source(file_path, **options)
        switch_to_source(source_id)
      end

      # Health check
      def healthy?
        return false if error?
        return true unless @current_source

        @current_source.running? && @main_buffer&.healthy? && @buffer_manager.stats[:health_status] == :healthy
      end

      private

      # Set up the main audio buffer for routing
      def setup_main_buffer
        @buffer_manager.create_buffer("main_audio", capacity: 8192)
        @main_buffer = @buffer_manager.get_buffer("main_audio")

        # Route main buffer to callback if registered
        @buffer_manager.route("main_audio") do |samples|
          @audio_callback&.call(samples)
        end
      end

      # Perform the actual source switch with optional fade
      def perform_source_switch(old_source, new_source_info, fade_duration)
        new_source = new_source_info[:source]

        begin
          # Fade out old source if requested and running
          fade_out_source(old_source, fade_duration) if old_source&.running? && fade_duration > 0

          # Stop old source
          old_source&.stop

          # Clear old audio data
          @main_buffer&.clear

          # Set up new source callback
          setup_source_callback(new_source)

          # Start new source if manager is supposed to be running
          if running? || @state == STATE_SWITCHING
            success = new_source.start
            fade_in_source(new_source, fade_duration) if success && fade_duration > 0
            success
          else
            true # Switch successful, but don't start yet
          end
        rescue StandardError => e
          @error_message = "Source switch failed: #{e.message}"
          false
        end
      end

      # Set up audio callback for a source
      def setup_source_callback(source)
        # Clear any existing callbacks
        source.clear_callbacks

        # Route audio data to main buffer
        source.on_audio_data do |audio_data|
          @buffer_manager.write_to_buffer("main_audio", audio_data)
        end
      end

      # Fade out audio source (simplified implementation)
      def fade_out_source(source, duration)
        return unless source.respond_to?(:set_volume)

        # This would require volume control - simplified for now
        sleep(duration)
      end

      # Fade in audio source (simplified implementation)
      def fade_in_source(source, duration)
        return unless source.respond_to?(:set_volume)

        # This would require volume control - simplified for now
        sleep(duration)
      end

      # Find or create system audio source
      def find_or_create_system_source(**options)
        existing = @available_sources.find { |_, info| info[:type] == SOURCE_SYSTEM }
        return existing.first if existing

        source_id = "system_#{Time.now.to_i}"
        create_source(source_id, type: SOURCE_SYSTEM, **options)
        source_id
      end

      # Find or create file audio source
      def find_or_create_file_source(file_path, **options)
        # Check for existing file source with same path
        existing = @available_sources.find do |_, info|
          info[:type] == SOURCE_FILE && info[:options][:file_path] == file_path
        end
        return existing.first if existing

        source_id = "file_#{File.basename(file_path, ".*")}_#{Time.now.to_i}"
        create_source(source_id, type: SOURCE_FILE, file_path: file_path, **options)
        source_id
      end

      # Validate source type
      def validate_source_type(type)
        valid_types = [SOURCE_SYSTEM, SOURCE_FILE]
        return if valid_types.include?(type)

        raise ArgumentError, "Invalid source type: #{type}. Must be one of: #{valid_types.join(", ")}"
      end

      # Calculate uptime
      def calculate_uptime
        # Simple uptime calculation - would need more sophisticated tracking
        0.0
      end
    end

    # Custom error for source management issues
    class SourceError < StandardError; end
  end
end
