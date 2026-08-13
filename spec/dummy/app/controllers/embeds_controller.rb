class EmbedsController < ActionController::Base
  protect_from_forgery with: :exception

  def show; end

  def broken; end

  def headless_erb; end

  def headless_haml; end

  def image
    render animate_it: { composition: "client-runtime-spec", frame: 3, props: {}, cache: true }
  end
end
