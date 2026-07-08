module AnimateIt
  # Engine base job. Standalone-safe: inherits ActiveJob::Base directly rather
  # than the host app's ApplicationJob, so the gem works in any host.
  class ApplicationJob < ActiveJob::Base
  end
end
