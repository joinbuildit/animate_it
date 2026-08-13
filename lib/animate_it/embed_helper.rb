require "json"

module AnimateIt
  class EmbedBuilder
    attr_reader :composition

    def initialize(view, composition, navigation: {})
      @view = view
      @composition = composition
      @navigation = navigation
    end

    def chapter_navigation(**attributes, &block)
      custom = block.present?
      preset = if attributes.key?(:preset)
                 attributes.delete(:preset)
               elsif !custom
                 @navigation.fetch(:preset, :pills)
               end
      mobile = if attributes.key?(:mobile)
                 attributes.delete(:mobile)
               elsif !custom
                 @navigation[:mobile]
               end
      style = ["--animate-it-chapter-count: #{@composition.chapters.count}", attributes.delete(:style)].compact.join(";")
      ChapterNavigationBuilder.new(@view, @composition, interactive: true, preset:, mobile:, frame: 0)
                              .render(**attributes, style:, &block)
    end
  end

  module EmbedHelper
    def animate_it_player(composition_id, title: nil, **attributes)
      composition = public_animate_it_composition!(composition_id)
      defaults = {
        src: animate_it_public_player_path(composition),
        title: title || composition.id,
        loading: "lazy",
        allow: "autoplay; fullscreen",
        allowfullscreen: true,
        style: "border:0;width:100%;aspect-ratio:#{composition.width}/#{composition.height}"
      }
      tag.iframe(**defaults, **attributes)
    end

    def animate_it_embed(
      composition_id,
      poster:,
      variants: [],
      navigation: { preset: :pills },
      load_when_visible: 0.25,
      play_when_visible: 2.0 / 3,
      pause_offscreen: true,
      reduced_motion: :poster,
      autoplay: true,
      title: nil,
      **attributes,
      &block
    )
      composition = public_animate_it_composition!(composition_id)
      navigation = navigation == false ? false : (navigation || {}).to_h.deep_symbolize_keys
      resolved_variants = resolve_animate_it_variants(composition, poster, variants)
      validate_animate_it_variant_chapters!(resolved_variants)
      manifest = animate_it_embed_manifest(
        title: title || composition.id,
        variants: resolved_variants,
        load_when_visible:,
        play_when_visible:,
        pause_offscreen:,
        reduced_motion:,
        autoplay:
      )
      builder = EmbedBuilder.new(self, composition, navigation: navigation || {})
      navigation_html = if navigation
                          block ? capture(builder, &block) : builder.chapter_navigation(class: "animate-it-embed__navigation")
                        end
      classes = ["animate-it-embed", attributes.delete(:class)].compact.join(" ")
      data = (attributes.delete(:data) || {}).merge(animate_it_embed: true)

      safe_join(
        [
          stylesheet_link_tag(animate_it_embed_asset_path("embed.css"), data: { animate_it_embed_asset: "style" }),
          javascript_include_tag(
            animate_it_embed_asset_path("embed.js"), defer: true, data: { animate_it_embed_asset: "script" }
          ),
          tag.public_send("animate-it-embed", **attributes, class: classes, data:) do
            safe_join([
              navigation_html,
              animate_it_embed_viewport(resolved_variants, title || composition.id),
              tag.script(ERB::Util.json_escape(JSON.generate(manifest)).html_safe,
                         type: "application/json", data: { animate_it_embed_manifest: true })
            ].compact)
          end
        ]
      )
    end

    private

    def public_animate_it_composition!(composition_id)
      AnimateIt.load_compositions!
      composition = AnimateIt.registry.fetch(composition_id)
      raise ArgumentError, "AnimateIt composition #{composition_id.inspect} is not public" unless composition.public_player?

      composition
    end

    def animate_it_mount_prefix
      respond_to?(:request) && request ? request.script_name.to_s : ""
    end

    def animate_it_public_player_path(composition)
      id = ERB::Util.url_encode(composition.id)
      "#{animate_it_mount_prefix}#{AnimateIt.config.mount_path}/public/compositions/#{id}/player"
    end

    def animate_it_embed_asset_path(filename)
      version = ERB::Util.url_encode(AnimateIt::VERSION)
      "#{animate_it_mount_prefix}#{AnimateIt.config.mount_path}/assets/#{version}/#{filename}"
    end

    def resolve_animate_it_variants(composition, poster, variants)
      raise ArgumentError, "animate_it_embed requires a poster" if poster.blank?

      primary = animate_it_variant_hash(composition, poster:, media: nil)
      responsive = Array(variants).map do |variant|
        attributes = variant.to_h.deep_symbolize_keys
        target = public_animate_it_composition!(attributes.fetch(:composition))
        media = attributes.fetch(:media).to_s
        raise ArgumentError, "AnimateIt variant media query must not be blank" if media.blank?

        animate_it_variant_hash(target, poster: attributes.fetch(:poster), media:)
      end
      duplicate_media = responsive.group_by { |variant| variant.fetch("media") }.select { |_media, group| group.many? }.keys
      raise ArgumentError, "AnimateIt variant media queries must be unique: #{duplicate_media.join(", ")}" if duplicate_media.any?

      [primary, *responsive]
    end

    def animate_it_variant_hash(composition, poster:, media:)
      raise ArgumentError, "AnimateIt variant poster must not be blank" if poster.blank?

      manifest = composition.player_manifest.as_json
      {
        "media" => media,
        "composition" => manifest,
        "poster" => poster.to_s,
        "source" => animate_it_public_player_path(composition)
      }
    end

    def validate_animate_it_variant_chapters!(variants)
      expected = variants.first.dig("composition", "chapters").map { |chapter| chapter.values_at("name", "label") }
      variants.drop(1).each do |variant|
        actual = variant.dig("composition", "chapters").map { |chapter| chapter.values_at("name", "label") }
        next if actual == expected

        raise ArgumentError, "AnimateIt responsive variants must expose the same ordered chapter names and labels"
      end
    end

    def animate_it_embed_manifest(title:, variants:, load_when_visible:, play_when_visible:, pause_offscreen:, reduced_motion:, autoplay:)
      load_ratio = Float(load_when_visible)
      play_ratio = Float(play_when_visible)
      unless load_ratio.between?(0, 1) && play_ratio.between?(0, 1)
        raise ArgumentError, "AnimateIt visibility thresholds must be between 0 and 1"
      end
      raise ArgumentError, "AnimateIt reduced_motion must be :poster" unless reduced_motion.to_s == "poster"

      {
        "version" => 1,
        "title" => title,
        "variants" => variants,
        "options" => {
          "loadWhenVisible" => load_ratio,
          "playWhenVisible" => play_ratio,
          "pauseOffscreen" => pause_offscreen == true,
          "reducedMotion" => reduced_motion.to_s,
          "autoplay" => autoplay == true,
          "readyTimeout" => 5000,
          "crossfadeDuration" => 120
        }
      }
    rescue TypeError, ArgumentError => e
      raise e if e.message.start_with?("AnimateIt")

      raise ArgumentError, "AnimateIt visibility thresholds must be numbers between 0 and 1"
    end

    def animate_it_embed_viewport(variants, title)
      primary = variants.first
      sources = variants.drop(1).map do |variant|
        tag.source(media: variant.fetch("media"), srcset: variant.fetch("poster"))
      end
      poster = tag.picture(
        safe_join([*sources, image_tag(primary.fetch("poster"), alt: title, loading: "eager")]),
        class: "animate-it-embed__poster", data: { animate_it_embed_poster: true }
      )
      viewport = tag.div(class: "animate-it-embed__viewport", data: { animate_it_embed_viewport: true }) do
        safe_join(
          [
            poster,
            tag.div(tag.div("", class: "animate-it-embed__frame", data: { animate_it_embed_frame: true }),
                    class: "animate-it-embed__shell", data: { animate_it_embed_shell: true }),
            tag.button(
              "Play", type: "button", class: "animate-it-embed__control", hidden: true,
                      data: { animate_it_embed_control: true }, aria: { label: "Play animation", pressed: "false" }
            )
          ]
        )
      end
      safe_join([viewport, tag.noscript(image_tag(primary.fetch("poster"), alt: title))])
    end
  end
end
