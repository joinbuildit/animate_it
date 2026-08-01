require "rails_helper"

RSpec.describe "AnimateIt gem package" do
  let(:root) { Pathname(__dir__).join("../..").expand_path }

  it "anchors its file list to the gem root when evaluated elsewhere" do
    Dir.mktmpdir("animate-it-package-host") do |directory|
      host_file = Pathname(directory).join("app/host-only.rb")
      FileUtils.mkdir_p(host_file.dirname)
      FileUtils.touch(host_file)

      specification = Dir.chdir(directory) do
        Gem::Specification.load(root.join("animate_it.gemspec").to_s)
      end

      expect(specification.files).not_to include("app/host-only.rb")
      expect(specification.files).to include(
        "app/views/animate_it/frames/player.html.haml",
        "lib/animate_it/runtime/runtime.js",
        "lib/animate_it/verification.rb",
        "README.md",
        "CHANGELOG.md",
        "MIT-LICENSE"
      )
      expect(specification.executables).to include("render_animate_it_video")
    end
  end
end
