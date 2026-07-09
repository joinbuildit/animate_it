require_relative "boot"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "active_job/railtie"

require "haml"
require "animate_it"

module Dummy
  class Application < Rails::Application
    # Pin the app root to spec/dummy. Without this, Rails' root auto-detection
    # walks up and finds the gem root (Gemfile/.git), which makes the app adopt
    # the engine's config/routes.rb as its own — drawing it twice.
    config.root = File.expand_path("..", __dir__)

    # Track whichever Rails the active Appraisal gemfile resolved (7.2 or 8.1),
    # so one dummy app boots correctly under every version in the test matrix.
    config.load_defaults "#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f

    config.eager_load = ENV["CI"].present?
    config.consider_all_requests_local = true
    config.action_dispatch.show_exceptions = :none

    # The dummy app has no credentials/master key; use a static test secret.
    config.secret_key_base = "animate_it_dummy_secret_key_base_for_specs_only"

    # Engine core has no database — keep the dummy app DB-free.
    config.api_only = false
  end
end
