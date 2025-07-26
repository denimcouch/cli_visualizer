# frozen_string_literal: true

RSpec.describe CliVisualizer do
  describe "module structure" do
    it "has a version number" do
      expect(CliVisualizer::VERSION).not_to be nil
      expect(CliVisualizer::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end

    it "provides version method" do
      expect(CliVisualizer.version).to eq(CliVisualizer::VERSION)
    end

    it "provides root method" do
      expect(CliVisualizer.root).to be_a(String)
      expect(File.exist?(CliVisualizer.root)).to be true
    end
  end

  describe "error classes" do
    it "defines custom error hierarchy" do
      expect(CliVisualizer::Error).to be < StandardError
      expect(CliVisualizer::AudioError).to be < CliVisualizer::Error
      expect(CliVisualizer::VisualizationError).to be < CliVisualizer::Error
      expect(CliVisualizer::ConfigurationError).to be < CliVisualizer::Error
      expect(CliVisualizer::PlatformError).to be < CliVisualizer::Error
    end
  end

  describe "module autoloading" do
    it "defines Audio module" do
      expect(defined?(CliVisualizer::Audio)).to be_truthy
    end

    it "defines Visualizer module" do
      expect(defined?(CliVisualizer::Visualizer)).to be_truthy
    end

    it "defines Renderer module" do
      expect(defined?(CliVisualizer::Renderer)).to be_truthy
    end

    it "defines UI module" do
      expect(defined?(CliVisualizer::UI)).to be_truthy
    end

    it "defines Config module" do
      expect(defined?(CliVisualizer::Config)).to be_truthy
    end

    it "defines Platform module" do
      expect(defined?(CliVisualizer::Platform)).to be_truthy
    end
  end
end
