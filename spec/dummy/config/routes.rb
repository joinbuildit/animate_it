Rails.application.routes.draw do
  get "embed-spec", to: "embeds#show"
  get "embed-broken-spec", to: "embeds#broken"
  get "embed-headless-erb", to: "embeds#headless_erb"
  get "embed-headless-haml", to: "embeds#headless_haml"
  mount AnimateIt::Engine, at: AnimateIt.config.mount_path
end
