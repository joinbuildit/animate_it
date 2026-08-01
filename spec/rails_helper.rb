require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

require_relative "dummy/config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "factory_bot"
require "faker"

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = false
  config.filter_rails_from_backtrace!

  config.before(:each, type: :request) do
    # Request specs default to host www.example.com, which Rails'
    # HostAuthorization blocks; use a loopback host the default permit list
    # (the 0.0.0.0/0 IP range) allows.
    host! "127.0.0.1"

    # Unit specs call AnimateIt.reset!, clearing the registry that request specs
    # rely on. Zeitwerk won't re-run the already-loaded fixtures' `id` DSL, so
    # re-register them directly (idempotent).
    AnimateIt.register(DummyMotionVideo)
    AnimateIt.register(DummyErbVideo)
    AnimateIt.register(ClientRuntimeSpecVideo) if defined?(ClientRuntimeSpecVideo)
  end
end
