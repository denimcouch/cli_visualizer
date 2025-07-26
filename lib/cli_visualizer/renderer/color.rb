# frozen_string_literal: true

module CliVisualizer
  module Renderer
    # Color support and terminal color detection
    # Provides ANSI color codes, terminal capability detection, and color palettes
    class Color
      # Color capability levels
      CAPABILITY_NONE = :none
      CAPABILITY_16 = :colors_16
      CAPABILITY_256 = :colors_256
      CAPABILITY_TRUECOLOR = :truecolor

      # Standard 16 colors (ANSI)
      COLORS_16 = {
        black: 0,
        red: 1,
        green: 2,
        yellow: 3,
        blue: 4,
        magenta: 5,
        cyan: 6,
        white: 7,
        bright_black: 8,
        bright_red: 9,
        bright_green: 10,
        bright_yellow: 11,
        bright_blue: 12,
        bright_magenta: 13,
        bright_cyan: 14,
        bright_white: 15
      }.freeze

      # Audio visualization color themes
      THEMES = {
        classic: {
          name: "Classic",
          description: "Traditional green terminal colors",
          colors: {
            low: :green,
            mid: :bright_green,
            high: :bright_yellow,
            peak: :bright_red,
            background: :black,
            text: :white
          }
        },
        spectrum: {
          name: "Spectrum",
          description: "Rainbow colors following audio spectrum",
          colors: {
            low: :red,
            mid: :yellow,
            high: :cyan,
            peak: :bright_white,
            background: :black,
            text: :white
          }
        },
        fire: {
          name: "Fire",
          description: "Warm fire-like colors",
          colors: {
            low: :red,
            mid: :bright_red,
            high: :bright_yellow,
            peak: :bright_white,
            background: :black,
            text: :bright_yellow
          }
        },
        ice: {
          name: "Ice",
          description: "Cool blue and cyan colors",
          colors: {
            low: :blue,
            mid: :bright_blue,
            high: :cyan,
            peak: :bright_white,
            background: :black,
            text: :bright_cyan
          }
        },
        matrix: {
          name: "Matrix",
          description: "Green matrix-style colors",
          colors: {
            low: :black,
            mid: :green,
            high: :bright_green,
            peak: :bright_white,
            background: :black,
            text: :bright_green
          }
        },
        neon: {
          name: "Neon",
          description: "Bright neon colors",
          colors: {
            low: :magenta,
            mid: :bright_magenta,
            high: :bright_cyan,
            peak: :bright_white,
            background: :black,
            text: :bright_white
          }
        },
        monochrome: {
          name: "Monochrome",
          description: "Black and white only",
          colors: {
            low: :black,
            mid: :white,
            high: :bright_white,
            peak: :bright_white,
            background: :black,
            text: :white
          }
        }
      }.freeze

      class << self
        # Detect terminal color capability
        def detect_capability
          # Check for truecolor support
          @capability ||= if supports_truecolor?
                            CAPABILITY_TRUECOLOR
                          elsif supports_256_colors?
                            CAPABILITY_256
                          elsif supports_16_colors?
                            CAPABILITY_16
                          else
                            CAPABILITY_NONE
                          end
        end

        # Check if terminal supports any colors
        def color_supported?
          detect_capability != CAPABILITY_NONE
        end

        # Check if terminal supports 16 colors
        def supports_16_colors?
          term = ENV.fetch("TERM", nil)
          return false unless term

          # Basic color support indicators
          !term.include?("mono") &&
            (term.include?("color") ||
             term.include?("xterm") ||
             term.include?("screen") ||
             term.include?("tmux") ||
             ENV.fetch("COLORTERM", nil))
        end

        # Check if terminal supports 256 colors
        def supports_256_colors?
          term = ENV.fetch("TERM", nil)
          return false unless term

          term.include?("256") ||
            term.include?("256color") ||
            ENV["COLORTERM"]&.include?("256")
        end

        # Check if terminal supports truecolor (24-bit)
        def supports_truecolor?
          colorterm = ENV.fetch("COLORTERM", nil)
          return false unless colorterm

          colorterm.include?("truecolor") ||
            colorterm.include?("24bit") ||
            colorterm == "gnome-terminal" ||
            colorterm == "konsole"
        end

        # Generate foreground color escape code
        def fg(color_spec)
          return "" unless color_supported?

          case detect_capability
          when CAPABILITY_TRUECOLOR
            fg_truecolor(color_spec)
          when CAPABILITY_256
            fg_256(color_spec)
          when CAPABILITY_16
            fg_16(color_spec)
          else
            ""
          end
        end

        # Generate background color escape code
        def bg(color_spec)
          return "" unless color_supported?

          case detect_capability
          when CAPABILITY_TRUECOLOR
            bg_truecolor(color_spec)
          when CAPABILITY_256
            bg_256(color_spec)
          when CAPABILITY_16
            bg_16(color_spec)
          else
            ""
          end
        end

        # Generate color escape sequence with text
        def colorize(text, fg_color: nil, bg_color: nil, bold: false, italic: false, underline: false)
          return text unless color_supported?

          codes = []
          codes << fg(fg_color) if fg_color
          codes << bg(bg_color) if bg_color
          codes << "1" if bold
          codes << "3" if italic
          codes << "4" if underline

          return text if codes.empty?

          "\e[#{codes.join(";")}m#{text}\e[0m"
        end

        # Generate gradient colors between two points
        def gradient(start_color, end_color, steps)
          return [start_color] * steps unless color_supported?
          return [start_color] if steps <= 1

          case detect_capability
          when CAPABILITY_TRUECOLOR
            gradient_truecolor(start_color, end_color, steps)
          when CAPABILITY_256
            gradient_256(start_color, end_color, steps)
          else
            gradient_16(start_color, end_color, steps)
          end
        end

        # Get color theme
        def theme(name)
          THEMES[name.to_sym] || THEMES[:classic]
        end

        # List available themes
        def available_themes
          THEMES.keys
        end

        # Reset all colors and formatting
        def reset
          color_supported? ? "\e[0m" : ""
        end

        # Convert intensity (0.0-1.0) to color using theme
        def intensity_to_color(intensity, theme_name = :classic)
          theme_colors = theme(theme_name)[:colors]

          case intensity
          when 0.0..0.25
            theme_colors[:low]
          when 0.25..0.5
            theme_colors[:mid]
          when 0.5..0.85
            theme_colors[:high]
          else
            theme_colors[:peak]
          end
        end

        # Convert frequency to color (bass=red, mid=yellow, treble=blue)
        def frequency_to_color(frequency, max_frequency = 20_000)
          return :white unless color_supported?

          ratio = frequency.to_f / max_frequency

          case ratio
          when 0.0..0.15    # Bass (20-3000 Hz)
            :red
          when 0.15..0.25   # Low-mid
            :bright_red
          when 0.25..0.4    # Mid (3000-8000 Hz)
            :yellow
          when 0.4..0.6     # High-mid
            :bright_yellow
          when 0.6..0.8     # Treble (8000-16000 Hz)
            :cyan
          else              # High treble (16000+ Hz)
            :bright_cyan
          end
        end

        private

        # 16-color foreground
        def fg_16(color)
          color_code = COLORS_16[color.to_sym]
          return "" unless color_code

          if color_code < 8
            "3#{color_code}"
          else
            "9#{color_code - 8}"
          end
        end

        # 16-color background
        def bg_16(color)
          color_code = COLORS_16[color.to_sym]
          return "" unless color_code

          if color_code < 8
            "4#{color_code}"
          else
            "10#{color_code - 8}"
          end
        end

        # 256-color foreground
        def fg_256(color)
          case color
          when Symbol
            # Convert from 16-color name if possible
            color_code = COLORS_16[color]
            color_code ? "38;5;#{color_code}" : fg_16(color)
          when Integer
            color >= 0 && color <= 255 ? "38;5;#{color}" : ""
          when Hash
            # RGB hash: {r: 255, g: 128, b: 0}
            if color[:r] && color[:g] && color[:b]
              color_256 = rgb_to_256(color[:r], color[:g], color[:b])
              "38;5;#{color_256}"
            else
              ""
            end
          else
            ""
          end
        end

        # 256-color background
        def bg_256(color)
          case color
          when Symbol
            color_code = COLORS_16[color]
            color_code ? "48;5;#{color_code}" : bg_16(color)
          when Integer
            color >= 0 && color <= 255 ? "48;5;#{color}" : ""
          when Hash
            if color[:r] && color[:g] && color[:b]
              color_256 = rgb_to_256(color[:r], color[:g], color[:b])
              "48;5;#{color_256}"
            else
              ""
            end
          else
            ""
          end
        end

        # Truecolor foreground
        def fg_truecolor(color)
          case color
          when Symbol
            # Fall back to 256-color for named colors
            fg_256(color)
          when Hash
            # RGB hash: {r: 255, g: 128, b: 0}
            if color[:r] && color[:g] && color[:b]
              r = [[color[:r], 0].max, 255].min
              g = [[color[:g], 0].max, 255].min
              b = [[color[:b], 0].max, 255].min
              "38;2;#{r};#{g};#{b}"
            else
              fg_256(color)
            end
          when String
            # Hex color: "#FF8000"
            if color.match?(/^#[0-9A-Fa-f]{6}$/)
              r = color[1..2].to_i(16)
              g = color[3..4].to_i(16)
              b = color[5..6].to_i(16)
              "38;2;#{r};#{g};#{b}"
            else
              ""
            end
          else
            fg_256(color)
          end
        end

        # Truecolor background
        def bg_truecolor(color)
          case color
          when Symbol
            bg_256(color)
          when Hash
            if color[:r] && color[:g] && color[:b]
              r = [[color[:r], 0].max, 255].min
              g = [[color[:g], 0].max, 255].min
              b = [[color[:b], 0].max, 255].min
              "48;2;#{r};#{g};#{b}"
            else
              bg_256(color)
            end
          when String
            if color.match?(/^#[0-9A-Fa-f]{6}$/)
              r = color[1..2].to_i(16)
              g = color[3..4].to_i(16)
              b = color[5..6].to_i(16)
              "48;2;#{r};#{g};#{b}"
            else
              ""
            end
          else
            bg_256(color)
          end
        end

        # Convert RGB to 256-color palette
        def rgb_to_256(r, g, b)
          # Clamp values
          r = [[r, 0].max, 255].min
          g = [[g, 0].max, 255].min
          b = [[b, 0].max, 255].min

          # Convert to 6x6x6 color cube (colors 16-231)
          r_index = (r * 5.0 / 255).round
          g_index = (g * 5.0 / 255).round
          b_index = (b * 5.0 / 255).round

          16 + (36 * r_index) + (6 * g_index) + b_index
        end

        # Generate gradient for 16-color terminals
        def gradient_16(start_color, end_color, steps)
          # Simple interpolation between named colors
          COLORS_16[start_color.to_sym] || 7
          COLORS_16[end_color.to_sym] || 7

          return [start_color, end_color][0, steps] if steps <= 2

          # Simple transition through color spectrum
          colors = []
          steps.times do |i|
            ratio = i.to_f / (steps - 1)

            colors << if ratio < 0.5
                        start_color
                      else
                        end_color
                      end
          end

          colors
        end

        # Generate gradient for 256-color terminals
        def gradient_256(start_color, end_color, steps)
          # Convert colors to RGB first
          start_rgb = color_to_rgb(start_color)
          end_rgb = color_to_rgb(end_color)

          return [start_color] * steps unless start_rgb && end_rgb

          colors = []
          steps.times do |i|
            ratio = i.to_f / (steps - 1)

            r = (start_rgb[:r] + ((end_rgb[:r] - start_rgb[:r]) * ratio)).round
            g = (start_rgb[:g] + ((end_rgb[:g] - start_rgb[:g]) * ratio)).round
            b = (start_rgb[:b] + ((end_rgb[:b] - start_rgb[:b]) * ratio)).round

            colors << rgb_to_256(r, g, b)
          end

          colors
        end

        # Generate gradient for truecolor terminals
        def gradient_truecolor(start_color, end_color, steps)
          start_rgb = color_to_rgb(start_color)
          end_rgb = color_to_rgb(end_color)

          return [start_color] * steps unless start_rgb && end_rgb

          colors = []
          steps.times do |i|
            ratio = i.to_f / (steps - 1)

            r = (start_rgb[:r] + ((end_rgb[:r] - start_rgb[:r]) * ratio)).round
            g = (start_rgb[:g] + ((end_rgb[:g] - start_rgb[:g]) * ratio)).round
            b = (start_rgb[:b] + ((end_rgb[:b] - start_rgb[:b]) * ratio)).round

            colors << { r: r, g: g, b: b }
          end

          colors
        end

        # Convert color specification to RGB values
        def color_to_rgb(color)
          case color
          when Symbol
            # Convert from 16-color names to approximate RGB
            case color
            when :black then { r: 0, g: 0, b: 0 }
            when :red then { r: 128, g: 0, b: 0 }
            when :green then { r: 0, g: 128, b: 0 }
            when :yellow then { r: 128, g: 128, b: 0 }
            when :blue then { r: 0, g: 0, b: 128 }
            when :magenta then { r: 128, g: 0, b: 128 }
            when :cyan then { r: 0, g: 128, b: 128 }
            when :white then { r: 192, g: 192, b: 192 }
            when :bright_black then { r: 128, g: 128, b: 128 }
            when :bright_red then { r: 255, g: 0, b: 0 }
            when :bright_green then { r: 0, g: 255, b: 0 }
            when :bright_yellow then { r: 255, g: 255, b: 0 }
            when :bright_blue then { r: 0, g: 0, b: 255 }
            when :bright_magenta then { r: 255, g: 0, b: 255 }
            when :bright_cyan then { r: 0, g: 255, b: 255 }
            when :bright_white then { r: 255, g: 255, b: 255 }
            else nil
            end
          when Hash
            color[:r] && color[:g] && color[:b] ? color : nil
          when String
            # Parse hex color
            if color.match?(/^#[0-9A-Fa-f]{6}$/)
              {
                r: color[1..2].to_i(16),
                g: color[3..4].to_i(16),
                b: color[5..6].to_i(16)
              }
            else
              nil
            end
          else
            nil
          end
        end
      end
    end
  end
end
