# AnimateIt configuration. The engine is loaded by Bundler from the
# `gem "animate_it"` line in the Gemfile, so no manual require here.
#
# Change `mount_path` to relocate the Studio UI; `config/routes.rb` mounts
# the engine at `AnimateIt.config.mount_path` (development/test only).
AnimateIt.configure do |config|
  config.mount_path = "/animate_it"

  # Experimental alternate frame capture. Chromium remains the default.
  # config.capture_backend = :auto
  # config.servo_endpoint = "http://127.0.0.1:4178"
  # config.servo_allowed_origins = ["http://127.0.0.1:3000"]

  # Required only for controller responses such as `render animate_it: ...`.
  # Keep disabled unless the app has a shared, writable Rails cache.
  # config.internal_rendering = Rails.env.local?
  # config.render_asset_origins = ["https://cdn.example.com"]
end
