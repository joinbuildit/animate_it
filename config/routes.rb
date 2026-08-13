AnimateIt::Engine.routes.draw do
  get "assets/:version/embed.js", to: "embed_assets#javascript", as: :embed_javascript,
                                  constraints: { version: /[0-9A-Za-z._-]+/ }
  get "assets/:version/embed.css", to: "embed_assets#stylesheet", as: :embed_stylesheet,
                                   constraints: { version: /[0-9A-Za-z._-]+/ }

  root "studio#index"

  get "public/compositions/:id/player", to: "public_players#show", as: :public_composition_player
  get "public/compositions/:id/audio/:index", to: "public_players#audio", as: :public_composition_audio,
                                              constraints: { index: /\d+/ }

  get "internal/render_pages/:token", to: "render_pages#show", as: :internal_render_page,
                                      constraints: { token: /[0-9A-Za-z_-]+/ }

  get "compositions/:id", to: "studio#show", as: :composition
  get "compositions/:id/frame/:frame", to: "frames#show", as: :composition_frame, constraints: { frame: /-?\d+/ }
  get "compositions/:id/filmstrip", to: "frames#filmstrip", as: :composition_filmstrip
  get "compositions/:id/player", to: "frames#player", as: :composition_player
  get "compositions/:id/audio/:index", to: "audio#show", as: :composition_audio, constraints: { index: /\d+/ }
  patch "compositions/:id/props", to: "props#update", as: :composition_props
  post "compositions/:id/renders", to: "renders#create", as: :composition_renders
  post "renders/:id/cancel", to: "renders#cancel", as: :cancel_render
  get "renders/:id", to: "renders#show", as: :render
end
