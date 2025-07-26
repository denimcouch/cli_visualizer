# frozen_string_literal: true

module CliVisualizer
  module Audio
    # Audio signal processor with FFT-based frequency analysis
    # Provides real-time frequency domain analysis for audio visualization
    class Processor
      # Default configuration
      DEFAULT_FFT_SIZE = 1024
      DEFAULT_OVERLAP = 0.5
      DEFAULT_WINDOW = :hanning

      # Supported FFT sizes (powers of 2)
      SUPPORTED_FFT_SIZES = [128, 256, 512, 1024, 2048, 4096].freeze

      # Supported window functions
      SUPPORTED_WINDOWS = %i[hanning hamming blackman rectangular].freeze

      attr_reader :fft_size, :sample_rate, :overlap, :window_type, :frequency_bins

      def initialize(sample_rate: 44_100, fft_size: DEFAULT_FFT_SIZE,
                     overlap: DEFAULT_OVERLAP, window: DEFAULT_WINDOW)
        @sample_rate = sample_rate
        @fft_size = fft_size
        @overlap = overlap
        @window_type = window

        validate_parameters!

        # Pre-computed values for efficiency (needed for window generation)
        @two_pi = 2.0 * Math::PI
        @fft_size_float = @fft_size.to_f

        @hop_size = (@fft_size * (1.0 - @overlap)).to_i
        @window = generate_window(@fft_size, @window_type)
        @frequency_bins = generate_frequency_bins

        # Audio buffer for windowed processing
        @audio_buffer = []
        @callbacks = []
      end

      # Register callback to receive frequency analysis results
      # Block will be called with { freqs: Array, magnitudes: Array, phases: Array }
      def on_frequency_data(&block)
        @callbacks << block if block
      end

      # Clear all frequency data callbacks
      def clear_callbacks
        @callbacks.clear
      end

      # Process audio samples and perform FFT analysis
      def process_samples(samples)
        return if samples.empty?

        # Add samples to buffer
        @audio_buffer.concat(samples)

        # Process overlapping windows
        while @audio_buffer.length >= @fft_size
          # Extract window of samples
          window_samples = @audio_buffer[0, @fft_size]

          # Perform windowed FFT analysis
          frequency_data = analyze_frequency_spectrum(window_samples)

          # Notify callbacks
          notify_frequency_callbacks(frequency_data)

          # Advance buffer by hop size
          @audio_buffer = @audio_buffer[@hop_size..] || []
        end
      end

      # Get frequency bin for a given frequency in Hz
      def frequency_to_bin(frequency)
        (frequency * @fft_size.to_f / @sample_rate).round
      end

      # Get frequency in Hz for a given bin
      def bin_to_frequency(bin)
        bin * @sample_rate.to_f / @fft_size
      end

      # Get frequency range for visualization (typically 0 to Nyquist)
      def frequency_range
        [0, @sample_rate / 2.0]
      end

      # Get magnitude spectrum bins up to Nyquist frequency
      def magnitude_bins_count
        (@fft_size / 2) + 1
      end

      private

      # Validate initialization parameters
      def validate_parameters!
        unless SUPPORTED_FFT_SIZES.include?(@fft_size)
          raise ArgumentError, "FFT size must be one of: #{SUPPORTED_FFT_SIZES.join(", ")}"
        end

        unless SUPPORTED_WINDOWS.include?(@window_type)
          raise ArgumentError, "Window type must be one of: #{SUPPORTED_WINDOWS.join(", ")}"
        end

        raise ArgumentError, "Overlap must be between 0.0 and 1.0 (exclusive)" unless @overlap >= 0.0 && @overlap < 1.0

        return if @sample_rate.positive?

        raise ArgumentError, "Sample rate must be positive"
      end

      # Generate window function coefficients
      def generate_window(size, type)
        case type
        when :hanning
          generate_hanning_window(size)
        when :hamming
          generate_hamming_window(size)
        when :blackman
          generate_blackman_window(size)
        when :rectangular
          Array.new(size, 1.0)
        else
          raise ArgumentError, "Unsupported window type: #{type}"
        end
      end

      # Generate Hanning window coefficients
      def generate_hanning_window(size)
        (0...size).map do |n|
          0.5 * (1.0 - Math.cos(@two_pi * n / (size - 1)))
        end
      end

      # Generate Hamming window coefficients
      def generate_hamming_window(size)
        (0...size).map do |n|
          0.54 - (0.46 * Math.cos(@two_pi * n / (size - 1)))
        end
      end

      # Generate Blackman window coefficients
      def generate_blackman_window(size)
        (0...size).map do |n|
          0.42 - (0.5 * Math.cos(@two_pi * n / (size - 1))) +
            (0.08 * Math.cos(4.0 * Math::PI * n / (size - 1)))
        end
      end

      # Generate frequency bins for the FFT output
      def generate_frequency_bins
        (0..(@fft_size / 2)).map do |bin|
          bin * @sample_rate.to_f / @fft_size
        end
      end

      # Perform windowed FFT analysis on audio samples
      def analyze_frequency_spectrum(samples)
        # Apply window function
        windowed_samples = apply_window(samples)

        # Perform FFT
        complex_spectrum = fft(windowed_samples)

        # Extract magnitude and phase (up to Nyquist frequency)
        magnitudes = []
        phases = []

        (0..(@fft_size / 2)).each do |i|
          real = complex_spectrum[i][:real]
          imag = complex_spectrum[i][:imag]

          magnitude = Math.sqrt((real * real) + (imag * imag))
          phase = Math.atan2(imag, real)

          magnitudes << magnitude
          phases << phase
        end

        {
          frequencies: @frequency_bins,
          magnitudes: magnitudes,
          phases: phases,
          sample_rate: @sample_rate,
          fft_size: @fft_size
        }
      end

      # Apply window function to samples
      def apply_window(samples)
        samples.each_with_index.map do |sample, i|
          sample * @window[i]
        end
      end

      # Cooley-Tukey FFT implementation
      # Input: array of real samples
      # Output: array of complex numbers {real:, imag:}
      def fft(samples)
        n = samples.length

        # Base case
        return [{ real: samples[0], imag: 0.0 }] if n == 1

        # Ensure input size is power of 2
        raise ArgumentError, "FFT size must be a power of 2" unless n.positive? && n.nobits?((n - 1))

        # Divide: separate even and odd samples
        even_samples = []
        odd_samples = []

        samples.each_with_index do |sample, i|
          if i.even?
            even_samples << sample
          else
            odd_samples << sample
          end
        end

        # Conquer: recursively compute FFT of even and odd parts
        even_fft = fft(even_samples)
        odd_fft = fft(odd_samples)

        # Combine: merge results
        result = Array.new(n)
        half_n = n / 2

        (0...half_n).each do |k|
          # Calculate twiddle factor
          angle = -@two_pi * k / n
          twiddle_real = Math.cos(angle)
          twiddle_imag = Math.sin(angle)

          # Complex multiplication: twiddle * odd_fft[k]
          odd_real = odd_fft[k][:real]
          odd_imag = odd_fft[k][:imag]

          t_real = (twiddle_real * odd_real) - (twiddle_imag * odd_imag)
          t_imag = (twiddle_real * odd_imag) + (twiddle_imag * odd_real)

          # Combine even and odd results
          even_real = even_fft[k][:real]
          even_imag = even_fft[k][:imag]

          result[k] = {
            real: even_real + t_real,
            imag: even_imag + t_imag
          }

          result[k + half_n] = {
            real: even_real - t_real,
            imag: even_imag - t_imag
          }
        end

        result
      end

      # Notify all frequency data callbacks
      def notify_frequency_callbacks(frequency_data)
        @callbacks.each { |callback| callback.call(frequency_data) }
      rescue StandardError => e
        # Don't let callback errors break processing
        warn "Frequency callback error: #{e.message}" if $VERBOSE
      end
    end
  end
end
