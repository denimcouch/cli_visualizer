# frozen_string_literal: true

module CliVisualizer
  # Main application controller for the CLI Audio Visualizer
  class Application
    def initialize(args = [])
      @args = args
    end

    def run
      case @args.first
      when "--version", "-v"
        puts "CLI Audio Visualizer v#{CliVisualizer.version}"
      when "--help", "-h", nil
        show_help
      else
        show_welcome
      end
    end

    private

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def show_welcome
      puts "CLI Audio Visualizer v#{CliVisualizer.version}"
      puts
      puts "🎵 Welcome to CLI Audio Visualizer! 🎵"
      puts
      puts "⚠️  This is currently under development."
      puts "   Audio visualization features are being implemented."
      puts
      puts "Run with --help to see available options."
      puts
      puts "Current status:"
      puts "✅ Project structure established"
      puts "✅ Ruby gem foundation complete"
      puts "✅ Testing framework configured"
      puts "✅ CI pipeline setup"
      puts "🚧 Audio capture system (next up!)"
      puts "🚧 Visualization engine"
      puts "🚧 Terminal rendering"
      puts
      puts "Stay tuned for real audio visualizations! 🎶"
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/MethodLength
    def show_help
      puts <<~HELP
        CLI Audio Visualizer v#{CliVisualizer.version}

        A real-time audio visualizer for your terminal.

        USAGE:
            cli_visualizer [OPTIONS]

        OPTIONS:
            -h, --help       Show this help message
            -v, --version    Show version information

        FEATURES (Coming Soon):
            🎶 Real-time audio visualization
            📊 Multiple visualization modes (spectrum, waveform, abstract)
            🎨 Customizable colors and patterns
            🔊 System audio capture or file playback
            ⚙️  Configurable sensitivity and display options
            🖥️  Cross-platform support (macOS, Linux)

        EXAMPLES:
            cli_visualizer              # Start with default settings
            cli_visualizer --help       # Show this help
            cli_visualizer --version    # Show version

        For more information, visit:
        https://github.com/denimcouch/cli_visualizer
      HELP
    end
    # rubocop:enable Metrics/MethodLength
  end
end
