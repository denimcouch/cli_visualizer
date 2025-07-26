# Task List: CLI Audio Visualizer Implementation

## Relevant Files

- `bin/cli_visualizer` - Main executable script for the CLI application (✅ CREATED)
- `exe/cli_visualizer` - Alternative executable created by bundle gem
- `.github/workflows/main.yml` - GitHub Actions CI workflow with multi-platform testing (✅ ENHANCED)
- `.git/hooks/pre-commit` - Pre-commit hook running RuboCop and RSpec (✅ CREATED)
- `.gitignore` - Comprehensive ignore patterns for Ruby, audio files, and development (✅ ENHANCED)
- `.rspec` - RSpec configuration with enhanced options (✅ ENHANCED)
- `Gemfile` - Gem dependencies including FFI, TTY gems, and dry-configurable (✅ ENHANCED)
- `cli_visualizer.gemspec` - Complete gem specification with metadata and dependencies (✅ ENHANCED)
- `Rakefile` - Rake tasks for running tests and linting (✅ CONFIGURED)
- `lib/cli_visualizer.rb` - Main library entry point and module definitions (✅ ENHANCED)
- `lib/cli_visualizer/version.rb` - Gem version definition (✅ CONFIGURED)
- `spec/spec_helper.rb` - RSpec configuration with testing utilities (✅ ENHANCED)
- `spec/cli_visualizer_spec.rb` - Main library tests for module structure (✅ ENHANCED)
- `spec/audio/` - Directory for audio capture and processing tests (✅ CREATED)
- `spec/visualizer/` - Directory for visualization mode tests (✅ CREATED)
- `spec/renderer/` - Directory for terminal rendering tests (✅ CREATED)
- `spec/ui/` - Directory for user interface tests (✅ CREATED)
- `spec/config/` - Directory for configuration management tests (✅ CREATED)
- `spec/platform/` - Directory for platform detection tests (✅ CREATED)
- `spec/fixtures/` - Directory for test data and fixtures (✅ CREATED)
- `lib/cli_visualizer/application.rb` - Main application controller and orchestration (✅ ENHANCED)
- `lib/cli_visualizer/audio/capture.rb` - Audio capture abstraction layer (✅ CREATED)
- `spec/audio/capture_spec.rb` - Audio capture abstraction tests (✅ CREATED)
- `spec/audio/file_player_spec.rb` - Audio file player tests (✅ CREATED)
- `spec/audio/file_player_integration_spec.rb` - Audio file player integration tests (✅ CREATED)
- `spec/audio/processor_spec.rb` - Audio processor and FFT analysis tests (✅ CREATED)
- `spec/audio/buffer_spec.rb` - Audio buffer tests (27 examples) (✅ CREATED)
- `spec/audio/buffer_manager_spec.rb` - Buffer manager and routing tests (34 examples) (✅ CREATED)
- `spec/audio/source_manager_spec.rb` - Source manager tests (35 examples) (✅ CREATED)
- `spec/audio/source_manager_integration_spec.rb` - Complete pipeline integration tests (9 examples) (✅ CREATED)
- `lib/cli_visualizer/audio/macos_capture.rb` - macOS-specific audio capture using Core Audio
- `lib/cli_visualizer/audio/linux_capture.rb` - Linux-specific audio capture using ALSA/PulseAudio
- `lib/cli_visualizer/audio/file_player.rb` - Audio file playback functionality (✅ CREATED)
- `lib/cli_visualizer/audio/processor.rb` - Audio signal processing (FFT, frequency analysis) (✅ CREATED)
- `lib/cli_visualizer/audio/buffer.rb` - Thread-safe circular audio buffer (✅ CREATED)
- `lib/cli_visualizer/audio/buffer_manager.rb` - Multi-buffer management and routing (✅ CREATED)
- `lib/cli_visualizer/audio/source_manager.rb` - Audio source switching and coordination (✅ CREATED)
- `lib/cli_visualizer/visualizer/base.rb` - Base class for all visualization modes
- `lib/cli_visualizer/visualizer/spectrum.rb` - Frequency spectrum bar visualization
- `lib/cli_visualizer/visualizer/waveform.rb` - Waveform pattern visualization
- `lib/cli_visualizer/visualizer/abstract.rb` - Abstract artistic pattern visualization
- `lib/cli_visualizer/renderer/terminal.rb` - Terminal output and ASCII rendering
- `lib/cli_visualizer/renderer/color.rb` - Color support and terminal color detection
- `lib/cli_visualizer/ui/keyboard.rb` - Keyboard input handling and shortcuts
- `lib/cli_visualizer/ui/controls.rb` - Runtime controls (pause, mode switching, etc.)
- `lib/cli_visualizer/config/manager.rb` - Configuration file management
- `lib/cli_visualizer/config/settings.rb` - User settings and preferences
- `lib/cli_visualizer/config/presets.rb` - Preset management system
- `lib/cli_visualizer/platform/detector.rb` - Platform detection utilities
- `spec/cli_visualizer_spec.rb` - Main library tests
- `spec/audio/capture_spec.rb` - Audio capture system tests
- `spec/audio/processor_spec.rb` - Audio processing tests
- `spec/visualizer/spectrum_spec.rb` - Spectrum visualizer tests
- `spec/visualizer/waveform_spec.rb` - Waveform visualizer tests
- `spec/renderer/terminal_spec.rb` - Terminal renderer tests
- `spec/config/manager_spec.rb` - Configuration management tests
- `Gemfile` - Ruby gem dependencies
- `cli_visualizer.gemspec` - Gem specification file
- `README.md` - Project documentation and usage guide
- `install.sh` - Installation script for system dependencies

### Notes

- Tests should be placed in the `spec/` directory following RSpec conventions
- Use `bundle exec rspec` to run the test suite
- Platform-specific code should be abstracted behind common interfaces
- Configuration files will be stored in the application directory as specified in PRD
- FFI (Foreign Function Interface) will be used for low-level audio system access

## Tasks

- [x] 1.0 Project Setup and Foundation

  - [x] 1.1 Initialize Ruby gem structure with `bundle gem cli_visualizer`
  - [x] 1.2 Configure Gemfile with necessary dependencies (rspec, ffi)
  - [x] 1.3 Set up CLI executable in `bin/cli_visualizer` with proper shebang
  - [x] 1.4 Create main library entry point `lib/cli_visualizer.rb`
  - [x] 1.5 Configure RSpec testing framework and directory structure
  - [x] 1.6 Set up basic Git workflow and .gitignore for Ruby projects
  - [x] 1.7 Create gemspec file with project metadata and dependencies
  - [x] 1.8 Set up github actions that run tests on every PR and push to main

- [ ] 2.0 Audio Capture and Processing System

  - [x] 2.1 Create audio capture abstraction layer in `lib/cli_visualizer/audio/capture.rb`
  - [x] 2.2 Implement macOS Core Audio integration using FFI
  - [x] 2.3 Implement Linux ALSA/PulseAudio integration using FFI
  - [x] 2.4 Build audio file player for MP3, WAV, FLAC support
  - [x] 2.5 Implement FFT-based frequency analysis in audio processor
  - [x] 2.6 Create audio buffer management for real-time processing
  - [x] 2.7 Add audio source switching mechanism (system vs file)
  - [ ] 2.8 Implement audio sensitivity and gain controls
  - [ ] 2.9 Add comprehensive tests for audio capture and processing

- [ ] 3.0 Visualization Engine and Rendering

  - [ ] 3.1 Create base visualization class with common interface
  - [ ] 3.2 Implement frequency spectrum bar visualizer (equalizer-style)
  - [ ] 3.3 Build waveform pattern visualization engine
  - [ ] 3.4 Create abstract artistic pattern generator
  - [ ] 3.5 Develop terminal ASCII renderer with animation support
  - [ ] 3.6 Add color support with terminal capability detection
  - [ ] 3.7 Implement visualization scaling for different terminal sizes
  - [ ] 3.8 Create ASCII character set options (basic vs extended)
  - [ ] 3.9 Build mode switching system between visualization types
  - [ ] 3.10 Add comprehensive tests for all visualization modes

- [ ] 4.0 User Interface and Controls

  - [ ] 4.1 Implement command-line argument parsing for initial configuration
  - [ ] 4.2 Create keyboard input handler for real-time controls
  - [ ] 4.3 Build pause/resume functionality for visualization
  - [ ] 4.4 Add keyboard shortcuts for mode switching and controls
  - [ ] 4.5 Implement real-time parameter adjustment (sensitivity, refresh rate)
  - [ ] 4.6 Create on-screen status indicators and help display
  - [ ] 4.7 Add graceful shutdown and cleanup on quit
  - [ ] 4.8 Implement error handling and user feedback system
  - [ ] 4.9 Add comprehensive tests for UI controls and keyboard handling

- [ ] 5.0 Configuration and Customization System

  - [ ] 5.1 Create configuration file manager for persistent settings
  - [ ] 5.2 Implement user settings system (colors, sensitivity, size)
  - [ ] 5.3 Build preset management for saving/loading configurations
  - [ ] 5.4 Add configuration validation and error handling
  - [ ] 5.5 Create default configuration templates
  - [ ] 5.6 Implement runtime configuration updates without restart
  - [ ] 5.7 Add comprehensive tests for configuration management

- [ ] 6.0 Cross-Platform Compatibility and Distribution
  - [ ] 6.1 Create platform detection system for macOS/Linux
  - [ ] 6.2 Build installation script for system dependencies
  - [ ] 6.3 Configure gem packaging and distribution
  - [ ] 6.4 Create comprehensive README with installation instructions
  - [ ] 6.5 Add platform-specific error handling and graceful fallbacks
  - [ ] 6.6 Implement dependency checking and system compatibility validation
  - [ ] 6.7 Create distribution package with install scripts
