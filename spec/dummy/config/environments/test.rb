Rails.application.configure do
  # The dummy app never edits code mid-run; disable reloading so the engine's
  # routes aren't re-drawn per request (which collides on the `root` name).
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.public_file_server.enabled = true
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
  config.active_support.deprecation = :stderr

  # Allow request specs (www.example.com) and the render-smoke Puma server
  # (127.0.0.1) through — drop host authorization entirely in the test app.
  config.middleware.delete ActionDispatch::HostAuthorization
end
