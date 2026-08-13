# frozen_string_literal: true

require "open3"
require "rails_helper"

RSpec.describe "release notes generator" do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:script) { root.join("bin/release_notes").to_s }

  it "builds a release description from the matching changelog section" do
    Dir.mktmpdir("animate-it-release-notes") do |directory|
      changelog = Pathname(directory).join("CHANGELOG.md")
      changelog.write(<<~MARKDOWN)
        # Changelog

        ## [1.2.3] - 2026-08-13

        ### Added
        - Navigable chapters.

        ## [1.2.2] - 2026-08-01

        ### Fixed
        - An older issue.
      MARKDOWN

      output, error, status = Open3.capture3("ruby", script, "1.2.3", changelog.to_s)

      expect(status).to be_success
      expect(error).to be_empty
      expect(output).to include("## Animate It 1.2.3", "### Added", "- Navigable chapters.")
      expect(output).to include('gem "animate_it", "~> 1.2.3"')
      expect(output).not_to include("An older issue")
    end
  end

  it "fails when the version has no curated release description" do
    Dir.mktmpdir("animate-it-release-notes") do |directory|
      changelog = Pathname(directory).join("CHANGELOG.md")
      changelog.write("# Changelog\n\n## [1.2.2]\n\n- Existing release.\n")

      _output, error, status = Open3.capture3("ruby", script, "1.2.3", changelog.to_s)

      expect(status).not_to be_success
      expect(error).to include("no release description for 1.2.3")
    end
  end

  it "fails when the matching release description is empty" do
    Dir.mktmpdir("animate-it-release-notes") do |directory|
      changelog = Pathname(directory).join("CHANGELOG.md")
      changelog.write("# Changelog\n\n## [1.2.3]\n\n## [1.2.2]\n\n- Existing release.\n")

      _output, error, status = Open3.capture3("ruby", script, "1.2.3", changelog.to_s)

      expect(status).not_to be_success
      expect(error).to include("empty release description for 1.2.3")
    end
  end
end
