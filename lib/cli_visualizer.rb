# frozen_string_literal: true

require_relative "cli_visualizer/version"

# Main module for the CLI Audio Visualizer gem
module CliVisualizer
  # Custom error classes
  class Error < StandardError; end
  class AudioError < Error; end
  class VisualizationError < Error; end
  class ConfigurationError < Error; end
  class PlatformError < Error; end

  # Load core components
  autoload :Application, "cli_visualizer/application"

  # Audio system components
  module Audio
    autoload :Capture, "cli_visualizer/audio/capture"
    autoload :MacOSCapture, "cli_visualizer/audio/macos_capture"
    autoload :LinuxCapture, "cli_visualizer/audio/linux_capture"
    autoload :FilePlayer, "cli_visualizer/audio/file_player"
    autoload :Processor, "cli_visualizer/audio/processor"
    autoload :Buffer, "cli_visualizer/audio/buffer"
    autoload :BufferManager, "cli_visualizer/audio/buffer_manager"
    autoload :SourceManager, "cli_visualizer/audio/source_manager"
    autoload :Controls, "cli_visualizer/audio/controls"
  end

  # Visualization system components
  module Visualizer
    autoload :Base, "cli_visualizer/visualizer/base"
    autoload :Spectrum, "cli_visualizer/visualizer/spectrum"
    autoload :Waveform, "cli_visualizer/visualizer/waveform"
    autoload :Abstract, "cli_visualizer/visualizer/abstract"
  end

  # Rendering system components
  module Renderer
    autoload :Terminal, "cli_visualizer/renderer/terminal"
    autoload :Color, "cli_visualizer/renderer/color"
  end

  # Visualization components
  module Visualizer
    autoload :Base, "cli_visualizer/visualizer/base"
    autoload :Spectrum, "cli_visualizer/visualizer/spectrum"
    autoload :Waveform, "cli_visualizer/visualizer/waveform"
    autoload :Abstract, "cli_visualizer/visualizer/abstract"
  end

  # Rendering components
  module Renderer
    autoload :Terminal, "cli_visualizer/renderer/terminal"
    autoload :Color, "cli_visualizer/renderer/color"
  end

  # User interface components
  module UI
    autoload :Keyboard, "cli_visualizer/ui/keyboard"
    autoload :Controls, "cli_visualizer/ui/controls"
  end

  # Configuration management
  module Config
    autoload :Manager, "cli_visualizer/config/manager"
    autoload :Settings, "cli_visualizer/config/settings"
    autoload :Presets, "cli_visualizer/config/presets"
  end

  # Platform utilities
  module Platform
    autoload :Detector, "cli_visualizer/platform/detector"
  end

  # Gem information
  def self.version
    VERSION
  end

  def self.root
    File.expand_path("..", __dir__)
  end
end
