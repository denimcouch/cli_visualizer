# frozen_string_literal: true

require_relative "base"

module CliVisualizer
  module Visualizer
    # Abstract artistic pattern generator
    # Creates creative visualizations using particle systems, geometric patterns, and artistic effects
    class Abstract < Base
      # Abstract visualization styles
      PATTERN_STYLES = %i[particles mandala spiral galaxy constellation fractal flow].freeze

      # Default settings
      DEFAULT_PATTERN = :particles
      DEFAULT_PARTICLE_COUNT = 50
      DEFAULT_DECAY_RATE = 0.95
      DEFAULT_COLOR_SHIFT = true
      DEFAULT_SYMMETRY = :none      # :none, :horizontal, :vertical, :radial
      DEFAULT_COMPLEXITY = :medium  # :low, :medium, :high

      # Visual characters organized by intensity and style
      PARTICLE_CHARS = %w[· ∘ ○ ● ◉ ⦿ ⬢ ⬣].freeze
      FLOW_CHARS = %w[┈ ┉ ╌ ╍ ⋯ … ∶ ∴].freeze
      GEOMETRIC_CHARS = %w[◦ ◯ ○ ● ◇ ◈ ◊ ♦].freeze
      FRACTAL_CHARS = %w[⋅ ∘ ○ ◯ ◉ ⦿ ⬟ ⬢].freeze

      attr_reader :pattern, :particle_count, :decay_rate, :color_shift, :symmetry, :complexity

      def initialize(
        pattern: DEFAULT_PATTERN,
        particle_count: DEFAULT_PARTICLE_COUNT,
        decay_rate: DEFAULT_DECAY_RATE,
        color_shift: DEFAULT_COLOR_SHIFT,
        symmetry: DEFAULT_SYMMETRY,
        complexity: DEFAULT_COMPLEXITY,
        **base_options
      )
        @pattern = validate_pattern(pattern)
        @particle_count = validate_positive_integer(particle_count, "Particle count")
        @decay_rate = validate_range(decay_rate, 0.1, 1.0, "Decay rate")
        @color_shift = color_shift
        @symmetry = validate_symmetry(symmetry)
        @complexity = validate_complexity(complexity)

        super(
          name: "Abstract",
          description: "Abstract artistic pattern visualization",
          **base_options
        )
      end

      protected

      def initialize_visualizer
        # Pattern-specific initialization
        case @pattern
        when :particles
          initialize_particle_system
        when :mandala
          initialize_mandala_system
        when :spiral
          initialize_spiral_system
        when :galaxy
          initialize_galaxy_system
        when :constellation
          initialize_constellation_system
        when :fractal
          initialize_fractal_system
        when :flow
          initialize_flow_system
        end

        # Common elements
        @center_x = @width / 2
        @center_y = @height / 2
        @max_radius = [[@width, @height].min / 2, 1].max

        # Animation state
        @frame_time = 0.0
        @last_audio_energy = 0.0
        @energy_history = []
      end

      def process_audio_data(samples)
        return if samples.empty?

        # Calculate audio energy and characteristics
        energy = calculate_audio_energy(samples)
        frequency_content = analyze_frequency_content(samples)

        # Update energy history for trends
        @energy_history << energy
        @energy_history.shift if @energy_history.length > 100

        @last_audio_energy = smooth_value(@last_audio_energy, energy, 0.7)

        # Update pattern based on audio characteristics
        update_pattern(energy, frequency_content, samples)
      end

      def process_frequency_analysis(frequency_data)
        return unless frequency_data.is_a?(Hash)
        return unless frequency_data[:magnitudes]

        # Use frequency data to influence pattern generation
        magnitudes = frequency_data[:magnitudes]
        @frequency_magnitudes = magnitudes.dup

        # Extract frequency band energies
        @bass_energy = magnitudes[0...magnitudes.length / 4].sum
        @mid_energy = magnitudes[magnitudes.length / 4...3 * magnitudes.length / 4].sum
        @treble_energy = magnitudes[3 * magnitudes.length / 4..-1].sum
      end

      def generate_frame_data
        @frame_time += 1.0 / @refresh_rate

        pattern_data = case @pattern
                       when :particles
                         generate_particle_pattern
                       when :mandala
                         generate_mandala_pattern
                       when :spiral
                         generate_spiral_pattern
                       when :galaxy
                         generate_galaxy_pattern
                       when :constellation
                         generate_constellation_pattern
                       when :fractal
                         generate_fractal_pattern
                       when :flow
                         generate_flow_pattern
                       else
                         generate_particle_pattern
                       end

        # Apply symmetry if enabled
        apply_symmetry(pattern_data) if @symmetry != :none

        {
          type: :abstract,
          pattern: @pattern,
          width: @width,
          height: @height,
          frame_time: @frame_time,
          audio_energy: @last_audio_energy,
          pattern_data: pattern_data,
          symmetry: @symmetry,
          complexity: @complexity
        }
      end

      def handle_resize(new_width, new_height)
        @center_x = new_width / 2
        @center_y = new_height / 2
        @max_radius = [[new_width, new_height].min / 2, 1].max
        initialize_visualizer
      end

      def supported_features
        %i[audio_energy frequency_analysis artistic_patterns particle_systems]
      end

      def default_config
        super.merge(
          pattern: DEFAULT_PATTERN,
          particle_count: DEFAULT_PARTICLE_COUNT,
          decay_rate: DEFAULT_DECAY_RATE,
          color_shift: DEFAULT_COLOR_SHIFT,
          symmetry: DEFAULT_SYMMETRY,
          complexity: DEFAULT_COMPLEXITY
        )
      end

      private

      # Audio analysis methods

      def calculate_audio_energy(samples)
        return 0.0 if samples.empty?

        rms = Math.sqrt(samples.map { |s| s * s }.sum / samples.length)
        [rms * 10, 1.0].min # Scale and clamp
      end

      def analyze_frequency_content(samples)
        return {} if samples.empty?

        # Simple frequency analysis - count zero crossings for rough frequency estimation
        zero_crossings = 0
        (1...samples.length).each do |i|
          zero_crossings += 1 if (samples[i] >= 0) != (samples[i - 1] >= 0)
        end

        dominant_frequency = (zero_crossings.to_f / samples.length) * 22_050 # Rough estimation

        {
          zero_crossings: zero_crossings,
          dominant_frequency: dominant_frequency,
          brightness: samples.map(&:abs).max,
          dynamics: calculate_dynamics(samples)
        }
      end

      def calculate_dynamics(samples)
        return 0.0 if samples.length < 2

        changes = 0
        (1...samples.length).each do |i|
          changes += 1 if (samples[i] - samples[i - 1]).abs > 0.1
        end

        changes.to_f / samples.length
      end

      # Pattern initialization methods

      def initialize_particle_system
        @particles = []
        @particle_count.times do |i|
          @particles << create_particle(i)
        end
      end

      def initialize_mandala_system
        @mandala_rings = []
        complexity_factor = complexity_to_factor
        (1..complexity_factor * 3).each do |ring|
          @mandala_rings << create_mandala_ring(ring)
        end
      end

      def initialize_spiral_system
        @spiral_arms = []
        arm_count = complexity_to_factor
        arm_count.times do |i|
          @spiral_arms << create_spiral_arm(i, arm_count)
        end
      end

      def initialize_galaxy_system
        @galaxy_arms = []
        @galaxy_core = { x: @center_x, y: @center_y, intensity: 1.0 }
        (0...4).each do |i|
          @galaxy_arms << create_galaxy_arm(i)
        end
      end

      def initialize_constellation_system
        @stars = []
        @constellations = []
        star_count = @particle_count
        star_count.times { @stars << create_star }
        create_constellation_connections
      end

      def initialize_fractal_system
        @fractal_depth = complexity_to_factor + 2
        @fractal_branches = []
        generate_fractal_tree
      end

      def initialize_flow_system
        @flow_field = []
        @flow_particles = []
        generate_flow_field
        @particle_count.times { @flow_particles << create_flow_particle }
      end

      # Pattern generation methods

      def generate_particle_pattern
        points = []

        @particles.each_with_index do |particle, i|
          # Update particle based on audio energy
          update_particle(particle, @last_audio_energy, i)

          # Generate visual point
          next unless particle[:life] > 0

          char = select_particle_char(particle)
          points << {
            x: particle[:x].round.clamp(0, @width - 1),
            y: particle[:y].round.clamp(0, @height - 1),
            char: char,
            intensity: particle[:life],
            velocity: particle[:velocity]
          }
        end

        points
      end

      def generate_mandala_pattern
        points = []

        @mandala_rings.each do |ring|
          update_mandala_ring(ring, @last_audio_energy)

          (0...ring[:segments]).each do |segment|
            angle = (2 * Math::PI * segment / ring[:segments]) + ring[:rotation]
            radius = ring[:base_radius] + (ring[:amplitude] * Math.sin(@frame_time * ring[:frequency]))

            x = @center_x + (radius * Math.cos(angle))
            y = @center_y + (radius * Math.sin(angle))

            next unless x >= 0 && x < @width && y >= 0 && y < @height

            char = GEOMETRIC_CHARS[(ring[:intensity] * (GEOMETRIC_CHARS.length - 1)).round]
            points << {
              x: x.round,
              y: y.round,
              char: char,
              intensity: ring[:intensity],
              ring: ring[:index]
            }
          end
        end

        points
      end

      def generate_spiral_pattern
        points = []

        @spiral_arms.each do |arm|
          update_spiral_arm(arm, @last_audio_energy)

          (0...arm[:segments]).each do |segment|
            t = segment.to_f / arm[:segments]
            angle = arm[:base_angle] + (t * arm[:turns] * 2 * Math::PI) + (@frame_time * arm[:speed])
            radius = t * @max_radius * arm[:radius_scale]

            x = @center_x + (radius * Math.cos(angle))
            y = @center_y + (radius * Math.sin(angle))

            next unless x >= 0 && x < @width && y >= 0 && y < @height

            intensity = arm[:intensity] * (1.0 - (t * 0.5)) # Fade toward outside
            char = FLOW_CHARS[(intensity * (FLOW_CHARS.length - 1)).round]

            points << {
              x: x.round,
              y: y.round,
              char: char,
              intensity: intensity,
              arm: arm[:index]
            }
          end
        end

        points
      end

      def generate_galaxy_pattern
        points = []

        # Galaxy core
        core_intensity = @galaxy_core[:intensity] * @last_audio_energy
        if core_intensity > 0.1
          points << {
            x: @galaxy_core[:x].round,
            y: @galaxy_core[:y].round,
            char: GEOMETRIC_CHARS.last,
            intensity: core_intensity,
            type: :core
          }
        end

        # Galaxy arms
        @galaxy_arms.each do |arm|
          update_galaxy_arm(arm, @last_audio_energy)

          (0...arm[:stars]).each do |star|
            t = star.to_f / arm[:stars]
            angle = arm[:base_angle] + (t * arm[:spiral_factor]) + (@frame_time * arm[:rotation_speed])
            radius = t * @max_radius * arm[:radius_scale]

            # Add some randomness
            radius += Math.sin((@frame_time * 2) + star) * arm[:turbulence]

            x = @center_x + (radius * Math.cos(angle))
            y = @center_y + (radius * Math.sin(angle))

            next unless x >= 0 && x < @width && y >= 0 && y < @height

            intensity = arm[:intensity] * (1.0 - (t * 0.3))
            char = PARTICLE_CHARS[(intensity * (PARTICLE_CHARS.length - 1)).round]

            points << {
              x: x.round,
              y: y.round,
              char: char,
              intensity: intensity,
              arm: arm[:index]
            }
          end
        end

        points
      end

      def generate_constellation_pattern
        points = []

        # Stars
        @stars.each do |star|
          update_star(star, @last_audio_energy)

          next unless star[:brightness] > 0.1

          char = PARTICLE_CHARS[(star[:brightness] * (PARTICLE_CHARS.length - 1)).round]
          points << {
            x: star[:x].round,
            y: star[:y].round,
            char: char,
            intensity: star[:brightness],
            type: :star
          }
        end

        # Constellation lines (simplified - just connect nearby bright stars)
        bright_stars = @stars.select { |s| s[:brightness] > 0.5 }
        bright_stars.each_with_index do |star1, i|
          bright_stars[(i + 1)..-1].each do |star2|
            distance = Math.sqrt(((star1[:x] - star2[:x])**2) + ((star1[:y] - star2[:y])**2))
            next if distance > @max_radius / 2

            # Draw line between stars (simplified)
            line_points = draw_line(star1[:x], star1[:y], star2[:x], star2[:y])
            line_points.each do |point|
              points << {
                x: point[:x],
                y: point[:y],
                char: "·",
                intensity: 0.3,
                type: :connection
              }
            end
          end
        end

        points
      end

      def generate_fractal_pattern
        points = []

        # Generate fractal tree based on audio energy
        generate_fractal_branch(
          @center_x, @center_y - (@height / 4),
          0, @max_radius / 2,
          @fractal_depth, points
        )

        points
      end

      def generate_flow_pattern
        points = []

        # Update flow particles
        @flow_particles.each do |particle|
          update_flow_particle(particle, @last_audio_energy)

          next unless particle[:life] > 0

          char = FLOW_CHARS[(particle[:intensity] * (FLOW_CHARS.length - 1)).round]
          points << {
            x: particle[:x].round.clamp(0, @width - 1),
            y: particle[:y].round.clamp(0, @height - 1),
            char: char,
            intensity: particle[:intensity],
            velocity: particle[:velocity]
          }
        end

        points
      end

      # Pattern update methods

      def update_pattern(energy, frequency_content, _samples)
        case @pattern
        when :particles
          # Spawn new particles based on energy
          if energy > 0.3 && @particles.count { |p| p[:life] > 0 } < @particle_count
            @particles << create_particle(rand(@particle_count))
          end
        when :mandala
          # Adjust mandala ring frequencies based on frequency content
          @mandala_rings.each do |ring|
            ring[:frequency] = 0.5 + (frequency_content[:dominant_frequency] / 1000.0)
          end
        when :spiral
          # Adjust spiral speed based on dynamics
          @spiral_arms.each do |arm|
            arm[:speed] = 0.1 + (frequency_content[:dynamics] * 2.0)
          end
        end
      end

      # Particle and element creation methods

      def create_particle(index)
        angle = rand * 2 * Math::PI
        speed = 0.5 + (rand * 2.0)

        {
          x: @center_x + ((rand - 0.5) * @width / 4),
          y: @center_y + ((rand - 0.5) * @height / 4),
          velocity_x: Math.cos(angle) * speed,
          velocity_y: Math.sin(angle) * speed,
          life: 1.0,
          max_life: 0.5 + (rand * 1.0),
          size: 0.5 + (rand * 1.0),
          index: index
        }
      end

      def create_mandala_ring(ring_index)
        base_radius = (ring_index * @max_radius) / 8.0
        {
          index: ring_index,
          base_radius: base_radius,
          amplitude: base_radius * 0.2,
          segments: 8 + (ring_index * 4),
          frequency: 0.5 + (ring_index * 0.3),
          rotation: 0.0,
          intensity: 0.8
        }
      end

      def create_spiral_arm(index, total_arms)
        {
          index: index,
          base_angle: (2 * Math::PI * index) / total_arms,
          turns: 2 + (rand * 3),
          speed: 0.1 + (rand * 0.5),
          radius_scale: 0.8 + (rand * 0.4),
          segments: 50,
          intensity: 0.7
        }
      end

      def create_galaxy_arm(index)
        {
          index: index,
          base_angle: (Math::PI * index) / 2,
          spiral_factor: 4 + (rand * 2),
          rotation_speed: 0.05 + (rand * 0.1),
          radius_scale: 0.9,
          stars: 30,
          turbulence: 2,
          intensity: 0.6
        }
      end

      def create_star
        {
          x: rand * @width,
          y: rand * @height,
          brightness: rand,
          base_brightness: rand,
          twinkle_speed: 0.5 + (rand * 2.0)
        }
      end

      def create_flow_particle
        {
          x: rand * @width,
          y: rand * @height,
          velocity_x: 0,
          velocity_y: 0,
          life: 1.0,
          intensity: 0.5,
          trail: []
        }
      end

      # Particle and element update methods

      def update_particle(particle, energy, _index)
        # Update position
        particle[:x] += particle[:velocity_x]
        particle[:y] += particle[:velocity_y]

        # Apply energy influence
        energy_influence = energy * 0.1
        particle[:velocity_x] += (rand - 0.5) * energy_influence
        particle[:velocity_y] += (rand - 0.5) * energy_influence

        # Apply decay
        particle[:life] *= @decay_rate

        # Boundary handling
        particle[:life] *= 0.9 if particle[:x] < 0 || particle[:x] >= @width || particle[:y] < 0 || particle[:y] >= @height

        # Gravitational pull toward center (gentle)
        center_pull = 0.01 * energy
        dx = @center_x - particle[:x]
        dy = @center_y - particle[:y]
        distance = Math.sqrt((dx * dx) + (dy * dy)) + 0.1

        particle[:velocity_x] += (dx / distance) * center_pull
        particle[:velocity_y] += (dy / distance) * center_pull
      end

      def update_mandala_ring(ring, energy)
        ring[:intensity] = smooth_value(ring[:intensity], energy, 0.8)
        ring[:rotation] += 0.01 + (energy * 0.05)
      end

      def update_spiral_arm(arm, energy)
        arm[:intensity] = smooth_value(arm[:intensity], energy, 0.7)
      end

      def update_galaxy_arm(arm, energy)
        arm[:intensity] = smooth_value(arm[:intensity], energy, 0.6)
      end

      def update_star(star, energy)
        # Twinkle effect
        twinkle = Math.sin(@frame_time * star[:twinkle_speed]) * 0.3
        star[:brightness] = star[:base_brightness] + twinkle + (energy * 0.2)
        star[:brightness] = [star[:brightness], 1.0].min
      end

      def update_flow_particle(particle, energy)
        # Simple flow field movement
        particle[:velocity_x] = Math.sin((particle[:y] * 0.1) + @frame_time) * energy
        particle[:velocity_y] = Math.cos((particle[:x] * 0.1) + @frame_time) * energy

        particle[:x] += particle[:velocity_x]
        particle[:y] += particle[:velocity_y]

        # Wrap around boundaries
        particle[:x] = particle[:x] % @width
        particle[:y] = particle[:y] % @height

        particle[:intensity] = energy
      end

      # Utility methods

      def select_particle_char(particle)
        intensity_index = (particle[:life] * (PARTICLE_CHARS.length - 1)).round
        PARTICLE_CHARS[intensity_index.clamp(0, PARTICLE_CHARS.length - 1)]
      end

      def apply_symmetry(pattern_data)
        case @symmetry
        when :horizontal
          pattern_data.concat(mirror_horizontal(pattern_data))
        when :vertical
          pattern_data.concat(mirror_vertical(pattern_data))
        when :radial
          3.times do |i|
            angle = (i + 1) * Math::PI / 2
            pattern_data.concat(rotate_pattern(pattern_data, angle))
          end
        end
      end

      def mirror_horizontal(points)
        points.map do |point|
          point.merge(x: @width - 1 - point[:x])
        end
      end

      def mirror_vertical(points)
        points.map do |point|
          point.merge(y: @height - 1 - point[:y])
        end
      end

      def rotate_pattern(points, angle)
        cos_a = Math.cos(angle)
        sin_a = Math.sin(angle)

        points.map do |point|
          # Translate to center, rotate, translate back
          x_centered = point[:x] - @center_x
          y_centered = point[:y] - @center_y

          new_x = (x_centered * cos_a) - (y_centered * sin_a) + @center_x
          new_y = (x_centered * sin_a) + (y_centered * cos_a) + @center_y

          point.merge(
            x: new_x.round.clamp(0, @width - 1),
            y: new_y.round.clamp(0, @height - 1)
          )
        end
      end

      def draw_line(x1, y1, x2, y2)
        points = []
        dx = (x2 - x1).abs
        dy = (y2 - y1).abs
        steps = [dx, dy].max

        return points if steps.zero?

        x_step = (x2 - x1).to_f / steps
        y_step = (y2 - y1).to_f / steps

        (0..steps).each do |i|
          x = (x1 + (i * x_step)).round
          y = (y1 + (i * y_step)).round
          next unless x >= 0 && x < @width && y >= 0 && y < @height

          points << { x: x, y: y }
        end

        points
      end

      def generate_fractal_branch(x, y, angle, length, depth, points)
        return if depth <= 0 || length < 1

        end_x = x + (length * Math.cos(angle))
        end_y = y + (length * Math.sin(angle))

        # Draw branch
        line_points = draw_line(x, y, end_x, end_y)
        line_points.each do |point|
          intensity = depth.to_f / @fractal_depth
          char = FRACTAL_CHARS[(intensity * (FRACTAL_CHARS.length - 1)).round]
          points << {
            x: point[:x],
            y: point[:y],
            char: char,
            intensity: intensity,
            depth: depth
          }
        end

        # Generate sub-branches
        branch_factor = 0.7 + (@last_audio_energy * 0.3)
        left_angle = angle - (Math::PI / 6)
        right_angle = angle + (Math::PI / 6)

        generate_fractal_branch(end_x, end_y, left_angle, length * branch_factor, depth - 1, points)
        generate_fractal_branch(end_x, end_y, right_angle, length * branch_factor, depth - 1, points)
      end

      def generate_flow_field
        # Create a simple flow field (simplified)
        @flow_field = Array.new(@height) { Array.new(@width, { x: 0, y: 0 }) }
      end

      def complexity_to_factor
        case @complexity
        when :low then 1
        when :medium then 2
        when :high then 3
        else 2
        end
      end

      # Validation methods

      def validate_pattern(pattern)
        raise ArgumentError, "Pattern must be one of: #{PATTERN_STYLES.join(", ")}" unless PATTERN_STYLES.include?(pattern)

        pattern
      end

      def validate_symmetry(symmetry)
        valid_symmetries = %i[none horizontal vertical radial]
        raise ArgumentError, "Symmetry must be one of: #{valid_symmetries.join(", ")}" unless valid_symmetries.include?(symmetry)

        symmetry
      end

      def validate_complexity(complexity)
        valid_complexities = %i[low medium high]
        unless valid_complexities.include?(complexity)
          raise ArgumentError, "Complexity must be one of: #{valid_complexities.join(", ")}"
        end

        complexity
      end

      # Configuration methods

      def set_pattern(new_pattern)
        @pattern = validate_pattern(new_pattern)
        initialize_visualizer
      end

      def set_particle_count(count)
        @particle_count = validate_positive_integer(count, "Particle count")
        initialize_visualizer if @pattern == :particles
      end

      def set_complexity(new_complexity)
        @complexity = validate_complexity(new_complexity)
        initialize_visualizer
      end

      def set_symmetry(new_symmetry)
        @symmetry = validate_symmetry(new_symmetry)
      end
    end
  end
end
