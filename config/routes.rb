AnimateIt::Engine.routes.draw do
  root "studio#index"

  get "compositions/:id", to: "studio#show", as: :composition
  get "compositions/:id/frame/:frame", to: "frames#show", as: :composition_frame, constraints: { frame: /-?\d+/ }
  get "compositions/:id/filmstrip", to: "frames#filmstrip", as: :composition_filmstrip
  get "compositions/:id/audio/:index", to: "audio#show", as: :composition_audio, constraints: { index: /\d+/ }
  patch "compositions/:id/props", to: "props#update", as: :composition_props
  post "compositions/:id/renders", to: "renders#create", as: :composition_renders
  post "renders/:id/cancel", to: "renders#cancel", as: :cancel_render
  get "renders/:id", to: "renders#show", as: :render
end
