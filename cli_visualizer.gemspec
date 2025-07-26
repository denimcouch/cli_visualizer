# frozen_string_literal: true

require_relative "lib/cli_visualizer/version"

Gem::Specification.new do |spec|
  spec.name = "cli_visualizer"
  spec.version = CliVisualizer::VERSION
  spec.authors = ["Alex Mata"]
  spec.email = ["alexmatasoftware@gmail.com"]

  spec.summary = "Real-time audio visualizer for the terminal"
  spec.description = <<~DESC
    CLI Audio Visualizer is a cross-platform command-line tool that creates real-time
    audio visualizations in your terminal. Features multiple visualization modes including
    frequency spectrum bars, waveform patterns, and abstract artistic displays. Supports
    both system audio capture and audio file playback with customizable colors, sensitivity,
    and display options.
  DESC
  spec.homepage = "https://github.com/denimcouch/cli_visualizer"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  # Gem metadata
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/denimcouch/cli_visualizer"
  spec.metadata["changelog_uri"] = "https://github.com/denimcouch/cli_visualizer/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/denimcouch/cli_visualizer/issues"
  spec.metadata["documentation_uri"] = "https://github.com/denimcouch/cli_visualizer/blob/main/README.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "dry-configurable", "~> 1.0"
  spec.add_dependency "ffi", "~> 1.15"
  spec.add_dependency "tty-cursor", "~> 0.7"
  spec.add_dependency "tty-screen", "~> 0.8"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"

  # Post-install message
  spec.post_install_message = <<~MSG
    Thank you for installing CLI Audio Visualizer!

    To get started, run:
      cli_visualizer --help

    For system audio capture, you may need to install platform-specific dependencies:
    - macOS: No additional dependencies required
    - Linux: ALSA or PulseAudio development headers may be needed

    Visit https://github.com/denimcouch/cli_visualizer for more information.
  MSG
end
