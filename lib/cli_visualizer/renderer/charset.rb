# frozen_string_literal: true

module CliVisualizer
  module Renderer
    # ASCII character set management for different terminal capabilities
    # Provides basic, extended, and Unicode character sets for visualizations
    class Charset
      # Character set types
      CHARSET_BASIC = :basic
      CHARSET_EXTENDED = :extended
      CHARSET_UNICODE = :unicode
      CHARSET_BLOCKS = :blocks

      # Basic ASCII character sets (7-bit ASCII, maximum compatibility)
      BASIC_SETS = {
        # Basic intensity levels (spaces and text characters)
        intensity: [" ", ".", ":", ";", "=", "+", "*", "#", "@"],

        # Simple bars using basic characters
        bars: [" ", ".", ":", "|", "#"],

        # Dots and periods
        dots: [" ", ".", ":", ";", ","],

        # Mathematical symbols available in basic ASCII
        math: [" ", ".", "-", "=", "+", "#"],

        # Waveform using basic characters
        waveform: [" ", ".", "-", "~", "^"],

        # Blocks using # character
        blocks: [" ", ".", ":", ";", "#"]
      }.freeze

      # Extended ASCII character sets (8-bit, more symbols available)
      EXTENDED_SETS = {
        # Smooth intensity gradients
        intensity: [" ", "░", "▒", "▓", "█"],

        # Vertical bars with varying heights
        bars: [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"],

        # Horizontal bars
        horizontal_bars: [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"],

        # Block elements
        blocks: [" ", "░", "▒", "▓", "█"],

        # Dots and circles
        dots: [" ", "·", "•", "●", "█"],

        # Waveform characters
        waveform: [" ", "▁", "▂", "▄", "▆", "█"],

        # Shading patterns
        shading: [" ", "░", "▒", "▓", "█"],

        # Geometric shapes
        geometric: [" ", "▫", "▪", "■", "█"]
      }.freeze

      # Unicode character sets (full Unicode support, best appearance)
      UNICODE_SETS = {
        # Braille patterns for high resolution
        braille: [
          " ", "⠁", "⠃", "⠇", "⠏", "⠟", "⠿", "⡿", "⣿"
        ],

        # Full block progression
        blocks: [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"],

        # Vertical lines
        vertical: [" ", "│", "┃", "║", "█"],

        # Smooth circles
        circles: [" ", "○", "◐", "◑", "◒", "◓", "●"],

        # Musical symbols
        musical: [" ", "♪", "♫", "♬", "♩", "♭", "♯"],

        # Arrows and symbols
        arrows: [" ", "↑", "↗", "→", "↘", "↓", "↙", "←", "↖"],

        # Stars and sparkles
        stars: [" ", "·", "✦", "✧", "✩", "✪", "✫", "★"],

        # Geometric progression
        geometric: [" ", "▫", "▪", "■", "█"],

        # Waveforms with smooth curves
        smooth_wave: [" ", "⎺", "⎻", "⎼", "⎽", "⎯"]
      }.freeze

      # Special character sets for specific visualizations
      SPECIAL_SETS = {
        # Fire/flame effect
        fire: ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "🔥"],

        # Water/wave effect
        water: ["▁", "▂", "▃", "∼", "≈", "∽", "〜", "💧"],

        # Lightning/energy
        lightning: [" ", "⚡", "✦", "✧", "✩", "✪", "⚡"],

        # Matrix rain effect
        matrix: ["0", "1", "|", ":", ".", "¦", "†", "‡"],

        # Equalizer bars
        equalizer: [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
      }.freeze

      class << self
        # Detect terminal character support
        def detect_capability
          @charset_capability ||= if supports_unicode?
                                    CHARSET_UNICODE
                                  elsif supports_extended_ascii?
                                    CHARSET_EXTENDED
                                  else
                                    CHARSET_BASIC
                                  end
        end

        # Check if terminal supports Unicode
        def supports_unicode?
          # Check environment variables for Unicode support
          lang = ENV["LANG"] || ENV["LC_ALL"] || ENV["LC_CTYPE"] || ""

          # Look for UTF-8 encoding
          lang.include?("UTF-8") || lang.include?("utf8") ||
            ENV["TERM"]&.include?("unicode") ||
            ENV["TERM"]&.include?("utf") ||
            utf8_locale?
        end

        # Check if terminal supports extended ASCII
        def supports_extended_ascii?
          term = ENV.fetch("TERM", nil)
          return true unless term # Assume extended ASCII if unknown

          # Most modern terminals support extended ASCII
          !term.include?("dumb") && !term.include?("ascii")
        end

        # Get character set for specific purpose
        def get_charset(purpose, type: nil)
          type ||= detect_capability

          case type
          when CHARSET_UNICODE
            get_unicode_charset(purpose)
          when CHARSET_EXTENDED
            get_extended_charset(purpose)
          else
            get_basic_charset(purpose)
          end
        end

        # Get character at specific intensity level (0.0-1.0)
        def char_at_intensity(intensity, charset_name, type: nil)
          charset = get_charset(charset_name, type: type)
          return " " if charset.empty?

          # Clamp intensity to valid range
          intensity = [[intensity, 0.0].max, 1.0].min

          # Map intensity to character index
          index = (intensity * (charset.length - 1)).round
          charset[index] || charset.last
        end

        # Create custom gradient charset
        def create_gradient(start_char, end_char, steps)
          return [start_char] if steps <= 1
          return [start_char, end_char] if steps == 2

          # For most cases, interpolate through available characters
          charset = get_charset(:intensity)
          start_idx = charset.index(start_char) || 0
          end_idx = charset.index(end_char) || (charset.length - 1)

          gradient = []
          steps.times do |i|
            ratio = i.to_f / (steps - 1)
            idx = (start_idx + ((end_idx - start_idx) * ratio)).round
            gradient << charset[idx]
          end

          gradient
        end

        # Get all available character sets for current terminal
        def available_charsets
          case detect_capability
          when CHARSET_UNICODE
            UNICODE_SETS.keys + EXTENDED_SETS.keys + BASIC_SETS.keys + SPECIAL_SETS.keys
          when CHARSET_EXTENDED
            EXTENDED_SETS.keys + BASIC_SETS.keys
          else
            BASIC_SETS.keys
          end
        end

        # Test character display in terminal
        def test_charset(charset_name, type: nil)
          charset = get_charset(charset_name, type: type)

          {
            name: charset_name,
            type: type || detect_capability,
            characters: charset,
            sample: charset.join(" "),
            length: charset.length
          }
        end

        # Get character for waveform at position
        def waveform_char(amplitude, position, style: :default)
          case style
          when :smooth
            get_smooth_waveform_char(amplitude, position)
          when :blocks
            get_block_waveform_char(amplitude, position)
          when :dots
            get_dot_waveform_char(amplitude, position)
          else
            get_default_waveform_char(amplitude, position)
          end
        end

        # Get character for spectrum bar
        def spectrum_char(intensity, style: :bars)
          char_at_intensity(intensity, style)
        end

        # Get escape sequences for box drawing
        def box_chars
          if supports_unicode?
            {
              horizontal: "─",
              vertical: "│",
              top_left: "┌",
              top_right: "┐",
              bottom_left: "└",
              bottom_right: "┘",
              cross: "┼",
              tee_up: "┴",
              tee_down: "┬",
              tee_left: "┤",
              tee_right: "├"
            }
          else
            {
              horizontal: "-",
              vertical: "|",
              top_left: "+",
              top_right: "+",
              bottom_left: "+",
              bottom_right: "+",
              cross: "+",
              tee_up: "+",
              tee_down: "+",
              tee_left: "+",
              tee_right: "+"
            }
          end
        end

        private

        # Check for UTF-8 locale
        def utf8_locale?
          locale_output = begin
            `locale charmap 2>/dev/null`.strip
          rescue StandardError
            nil
          end
          locale_output&.include?("UTF-8")
        end

        # Get Unicode character set
        def get_unicode_charset(purpose)
          UNICODE_SETS[purpose] || SPECIAL_SETS[purpose] || UNICODE_SETS[:blocks]
        end

        # Get extended ASCII character set
        def get_extended_charset(purpose)
          EXTENDED_SETS[purpose] || BASIC_SETS[purpose] || EXTENDED_SETS[:intensity]
        end

        # Get basic ASCII character set
        def get_basic_charset(purpose)
          BASIC_SETS[purpose] || BASIC_SETS[:intensity]
        end

        # Smooth waveform character selection
        def get_smooth_waveform_char(amplitude, position)
          if supports_unicode?
            UNICODE_SETS[:smooth_wave]
          else
            BASIC_SETS[:waveform]
          end

          char_at_intensity(amplitude.abs, :waveform)
        end

        # Block-style waveform character
        def get_block_waveform_char(amplitude, position)
          char_at_intensity(amplitude.abs, :blocks)
        end

        # Dot-style waveform character
        def get_dot_waveform_char(amplitude, position)
          char_at_intensity(amplitude.abs, :dots)
        end

        # Default waveform character selection
        def get_default_waveform_char(amplitude, position)
          char_at_intensity(amplitude.abs, :intensity)
        end
      end

      # Instance methods for stateful charset management
      attr_reader :current_type, :current_charsets

      def initialize(type: nil)
        @current_type = type || self.class.detect_capability
        @current_charsets = {}
        preload_charsets
      end

      # Get character set with caching
      def charset(purpose)
        @current_charsets[purpose] ||= self.class.get_charset(purpose, type: @current_type)
      end

      # Change character set type
      def change_type(new_type)
        return if new_type == @current_type

        @current_type = new_type
        @current_charsets.clear
        preload_charsets
      end

      # Get character at intensity with caching
      def char(purpose, intensity)
        charset = charset(purpose)
        return " " if charset.empty?

        intensity = [[intensity, 0.0].max, 1.0].min
        index = (intensity * (charset.length - 1)).round
        charset[index] || charset.last
      end

      private

      # Preload commonly used character sets
      def preload_charsets
        common_sets = %i[intensity bars blocks waveform]
        common_sets.each { |purpose| charset(purpose) }
      end
    end
  end
end
