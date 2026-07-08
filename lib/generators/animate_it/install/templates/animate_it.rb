# AnimateIt configuration. The engine is loaded by Bundler from the
# `gem "animate_it"` line in the Gemfile, so no manual require here.
#
# Change `mount_path` to relocate the Studio UI; `config/routes.rb` mounts
# the engine at `AnimateIt.config.mount_path` (development/test only).
AnimateIt.configure do |config|
  config.mount_path = "/animate_it"
end
