Rails.application.routes.draw do
  mount AnimateIt::Engine, at: AnimateIt.config.mount_path
end
