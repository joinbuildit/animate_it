module AnimateIt
  module EmbedHelper
    def animate_it_player(composition_id, title: nil, **attributes)
      AnimateIt.load_compositions!
      composition = AnimateIt.registry.fetch(composition_id)
      raise ArgumentError, "AnimateIt composition #{composition_id.inspect} is not public" unless composition.public_player?

      prefix = respond_to?(:request) && request ? request.script_name.to_s : ""
      source = "#{prefix}#{AnimateIt.config.mount_path}/public/compositions/" \
               "#{ERB::Util.url_encode(composition.id)}/player"
      defaults = {
        src: source,
        title: title || composition.id,
        loading: "lazy",
        allow: "autoplay; fullscreen",
        allowfullscreen: true,
        style: "border:0;width:100%;aspect-ratio:#{composition.width}/#{composition.height}"
      }
      tag.iframe(**defaults, **attributes)
    end
  end
end
