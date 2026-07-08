require_relative "lib/animate_it/version"

Gem::Specification.new do |spec|
  spec.name        = "animate_it"
  spec.version     = AnimateIt::VERSION
  spec.authors     = ["growth-constant"]
  spec.summary     = "Declarative, frame-driven video compositions for Rails, rendered with Playwright + FFmpeg"
  spec.description = <<~DESC
    AnimateIt is a mountable Rails engine for building videos as code. Declare a
    composition (size, fps, duration, beats, audio), describe each frame with a
    Ruby + HAML scene, preview it in the bundled Studio UI, and render it to
    MP4/WebM/MOV/GIF with a headless Chromium (Playwright) frame capture piped
    through FFmpeg.
  DESC
  spec.homepage    = "https://github.com/growth-constant/animate_it"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["homepage_uri"]          = spec.homepage
  spec.metadata["source_code_uri"]       = spec.homepage
  spec.metadata["changelog_uri"]         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]       = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["{app,config,lib}/**/*", "MIT-LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir      = "exe"
  spec.executables = Dir["exe/*"].map { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 8.1.3"
end
