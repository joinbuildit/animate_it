require_relative "lib/animate_it/version"

Gem::Specification.new do |spec|
  spec.name        = "animate_it"
  spec.version     = AnimateIt::VERSION
  spec.authors     = ["growth-constant"]
  spec.summary     = "Remotion for Rails — make videos with your app's own assets, in Ruby. No React required."
  spec.description = <<~DESC
    AnimateIt brings Remotion-style programmatic video to Ruby on Rails — without
    React or a JavaScript project. Build videos as code: a Ruby class plus a HAML
    template, using your app's own components, styles, fonts, and real data. Every
    frame is a real web page, so anything you can render in your app you can put in
    a video. Preview frame-by-frame in the bundled Studio, then export to
    MP4/WebM/MOV/GIF with headless Chromium (Playwright) + FFmpeg.

    Built for indie hackers and Rails developers who want to promote their projects
    with polished product demos, launch clips, and social ads — without leaving
    Ruby, hiring an editor, or learning After Effects.
  DESC
  spec.homepage    = "https://github.com/joinbuildit/animate_it"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"]          = spec.homepage
  spec.metadata["source_code_uri"]       = spec.homepage
  spec.metadata["changelog_uri"]         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]       = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["{app,config,exe,lib}/**/*", "servo-renderer/{Cargo.lock,Cargo.toml,README.md,src/**/*}",
        "CHANGELOG.md", "MIT-LICENSE", "README.md"].select do |path|
      File.file?(path)
    end
  end
  spec.bindir      = "exe"
  spec.executables = Dir.chdir(__dir__) { Dir["exe/*"].map { |path| File.basename(path) } }
  spec.require_paths = ["lib"]

  spec.add_dependency "haml", ">= 6.3"
  spec.add_dependency "rails", ">= 7.2"
end
