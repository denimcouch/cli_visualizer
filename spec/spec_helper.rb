# frozen_string_literal: true

require "cli_visualizer"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Configure test output
  config.formatter = :documentation
  config.color = true

  # Run specs in random order to surface order dependencies
  config.order = :random

  # Kernel.srand config.seed to support deterministic test order
  Kernel.srand config.seed

  # Filter out external gems from backtrace
  config.filter_gems_from_backtrace "ffi", "tty-cursor", "tty-screen"

  # Shared context for audio testing
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Configure warnings
  config.warnings = true

  # Enable pending specs
  config.run_all_when_everything_filtered = true

  # Configure before/after hooks
  config.before(:each) do
    # Reset any global state before each test
    allow($stdout).to receive(:write).and_call_original
    allow($stderr).to receive(:write).and_call_original
  end

  config.after(:each) do
    # Clean up any test artifacts
  end
end

# Helper methods for testing
def test_data_path
  File.join(File.dirname(__FILE__), "fixtures")
end

def capture_output
  original_stdout = $stdout
  original_stderr = $stderr
  $stdout = fake_stdout = StringIO.new
  $stderr = fake_stderr = StringIO.new
  yield
  { stdout: fake_stdout.string, stderr: fake_stderr.string }
ensure
  $stdout = original_stdout
  $stderr = original_stderr
end
