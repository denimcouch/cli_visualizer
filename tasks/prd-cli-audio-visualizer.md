# Product Requirements Document: CLI Audio Visualizer

## Introduction/Overview

The CLI Audio Visualizer is a Ruby-based command-line application that creates real-time ASCII art patterns based on audio input. This tool is designed to provide entertainment and visual appeal for CLI users who want to see their audio come to life in the terminal while listening to music or analyzing audio files.

The primary goal is to create an engaging, customizable audio visualization experience that works seamlessly across different terminal environments on macOS and Linux systems.

## Goals

1. **Primary Goal**: Create an entertaining ASCII-based audio visualizer that responds to audio in real-time
2. **Accessibility**: Ensure compatibility with any terminal/shell environment
3. **Flexibility**: Support multiple audio input sources (system audio and audio files)
4. **Customization**: Provide extensive user configuration options for personalized experiences
5. **Performance**: Maintain smooth real-time visualization with adjustable performance settings
6. **Cross-platform**: Support both macOS and Linux operating systems

## User Stories

**As a CLI enthusiast**, I want to visualize my music in the terminal so that I can have an engaging visual experience while working or listening to music.

**As a terminal user**, I want to cycle through different visualization modes so that I can find the style that best matches my current mood or audio type.

**As a developer**, I want to analyze audio files visually so that I can better understand their frequency patterns and characteristics.

**As a power user**, I want to customize colors, sensitivity, and visualization parameters so that the tool adapts to my preferences and system capabilities.

## Functional Requirements

### Core Functionality

1. The application must capture and process audio input in real-time
2. The system must generate ASCII patterns that respond to audio frequency and amplitude data
3. The application must provide multiple visualization modes that users can cycle through
4. The system must support real-time updates with smooth animation in the terminal

### Audio Input Sources

5. The application must support system audio output capture (what's currently playing)
6. The application must support audio file playback and visualization
7. Users must be able to switch between input sources during runtime

### Visualization Modes

9. The system must include a frequency spectrum bar visualization (equalizer-style)
10. The application must provide waveform pattern visualization
11. The system must offer abstract artistic patterns that respond to audio characteristics
12. Users must be able to cycle through visualization modes using keyboard shortcuts

### User Controls

13. The application must support pause/resume functionality for visualization
14. Users must be able to adjust refresh rate and sensitivity settings
15. The system must provide keyboard shortcuts for common actions (pause, mode switching, quit)
16. The application must allow real-time parameter adjustments without restarting

### Customization Options

17. The system must support color customization (when terminal supports colors)
18. Users must be able to adjust visualization size and scale
19. The application must provide audio sensitivity and gain controls
20. The system must support different ASCII character sets for pattern generation
21. Users must be able to save and load configuration presets

### Platform Compatibility

22. The application must work on macOS systems
23. The system must work on Linux distributions
24. The application must be compatible with common terminal applications (Terminal.app, iTerm2, gnome-terminal, etc.)
25. The system must work across different shell environments (bash, zsh, fish, etc.)

## Non-Goals (Out of Scope)

- **Windows Support**: Initial version will not support Windows (may be added in future versions)
- **GUI Interface**: This is strictly a command-line application with no graphical interface
- **Audio Recording/Saving**: The tool visualizes audio but does not record or save audio data
- **Network Audio Streaming**: No support for network-based audio sources
- **Plugin Architecture**: No extensible plugin system for custom visualizations
- **Audio Effects/Processing**: The tool only visualizes audio, it does not modify or process audio output
- **Multi-channel Audio Analysis**: Focus on stereo/mono audio, no complex surround sound analysis

## Design Considerations

### Terminal Compatibility

- Must work with standard 80x24 terminal sizes as baseline
- Should scale gracefully to larger terminal windows
- Must handle terminals with limited color support (fallback to monochrome)
- Should respect terminal color schemes and themes

### ASCII Art Patterns

- Use standard ASCII characters that display consistently across terminals
- Provide options for different character sets (basic ASCII vs extended characters)
- Design patterns that are visually appealing at different scales
- Ensure patterns remain recognizable even with limited terminal colors

### User Interface

- Command-line arguments for initial configuration
- Interactive keyboard shortcuts for runtime control
- Clear on-screen indicators for current mode and settings
- Minimal text overlay that doesn't interfere with visualization

## Technical Considerations

### Ruby Implementation

- Use pure Ruby where possible to minimize dependencies, consult user if gem dependency is needed.
- Target Ruby 3.3+ for broad compatibility
- Consider using FFI (Foreign Function Interface) for low-level audio system access
- Implement modular architecture for easy testing and maintenance

### Audio System Integration

- macOS: Integrate with Core Audio framework
- Linux: Use ALSA or PulseAudio for audio capture
- Handle different audio sample rates and bit depths
- Implement proper audio buffer management for smooth visualization

### Performance Requirements

- Target 30-60 FPS for smooth visualization
- Implement efficient audio processing algorithms
- Use appropriate threading for audio capture vs. visualization rendering
- Provide performance adjustment options for different system capabilities

### Dependencies

- Minimize external gem dependencies where possible
- Use well-maintained, stable libraries for audio processing
- Ensure all dependencies are available on both macOS and Linux
- Document all system-level dependencies clearly

## Success Metrics

1. **User Engagement**: Users run the application for extended periods (>5 minutes average session)
2. **Compatibility**: Successfully runs on 95%+ of tested terminal/shell combinations
3. **Performance**: Maintains consistent frame rate (>20 FPS) on mid-range hardware
4. **User Satisfaction**: Positive feedback on visualization quality and responsiveness
5. **Adoption**: Active usage across different user types (developers, music enthusiasts, CLI users)
6. **Stability**: <1% crash rate during normal operation

## Open Questions

1. **Audio Latency**: What level of audio-to-visual latency is acceptable for real-time feel? (Target: <100ms)
2. **System Permissions**: How should the application handle audio permission requests on macOS? yes
3. **Resource Usage**: What are acceptable CPU and memory usage limits during operation? should be minimal impact on CPU and memory usage
4. **Configuration Storage**: Where should user preferences be stored? (~/.config/ vs application directory) in application directory
5. **Error Handling**: How should the application behave when audio devices are unavailable or disconnected? show text saying "no audio source detected."
6. **Package Distribution**: Should this be distributed as a gem, or include installation scripts for system dependencies? include install scripts
7. **Audio Format Support**: What audio formats should be supported for file playback? (Start with common formats: MP3, WAV, FLAC? yes)

## Implementation Priority

### Phase 1 (MVP)

- Basic audio capture (system audio)
- Simple frequency spectrum visualization
- Basic terminal output and keyboard controls
- macOS support

### Phase 2

- Multiple visualization modes
- Audio file playback support
- Customization options (colors, sensitivity)
- Linux support

### Phase 3

- Advanced configuration and presets
- Performance optimizations
- Enhanced visualization modes
