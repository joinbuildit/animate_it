module AnimateIt
  # Declarative word-by-word headline reveals that can be recorded as compact
  # keyframe tracks while retaining server-rendered fallback values.
  module TextEffects
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def word_reveal(key, text, start:, offset: 0, stagger: 4, dur: 12, rise: 18)
        own_word_reveals[key.to_sym] = { kind: :rise, text:, start:, offset:, stagger:, dur:, rise: }
      end

      def punch_reveal(key, text, start:, offset: 0, stagger: 5, dur: 10)
        own_word_reveals[key.to_sym] = { kind: :punch, text:, start:, offset:, stagger:, dur: }
      end

      def word_reveals_registry
        inherited = superclass.respond_to?(:word_reveals_registry) ? superclass.word_reveals_registry : {}
        inherited.merge(own_word_reveals)
      end

      def own_word_reveals
        @own_word_reveals ||= {}
      end
    end

    def word_reveal_tracks(key)
      spec = self.class.word_reveals_registry.fetch(key.to_sym)
      base = resolve_reveal_start(spec)
      spec[:text].split.each_with_index.flat_map do |_word, index|
        from = base + (index * spec[:stagger])
        to = from + spec[:dur]
        if spec[:kind] == :punch
          [
            { var: "#{key}-w#{index}-op", frames: [from, to], values: [0, 1], unit: "" },
            {
              var: "#{key}-w#{index}-sc",
              frames: [from, from + (spec[:dur] * 0.6).round, to],
              values: [1.3, 1.06, 1.0],
              unit: ""
            }
          ]
        else
          [
            { var: "#{key}-w#{index}-op", frames: [from, to], values: [0, 1], unit: "" },
            { var: "#{key}-w#{index}-y", frames: [from, to], values: [spec[:rise], 0], unit: "px" }
          ]
        end
      end
    end

    def reveal_words(key)
      spec = self.class.word_reveals_registry.fetch(key.to_sym)
      static = word_reveal_tracks(key).to_h do |track|
        value = interpolate(
          local_frame,
          track[:frames],
          track[:values],
          easing: :ease_out,
          extrapolate_left: :clamp,
          extrapolate_right: :clamp
        ).round(4)
        [track[:var].to_sym, "#{value}#{track[:unit]}"]
      end

      spans = spec[:text].split.each_with_index.map do |word, index|
        tag.span(word, style: reveal_word_style(spec, key, index))
      end

      tag.span(
        safe_join(spans, " "),
        data: { animate_vars: reveal_group(key) },
        style: Style.build("display: contents", Style.vars(**static))
      )
    end

    def reveal_plain_words(key)
      spec = self.class.word_reveals_registry.fetch(key.to_sym)
      safe_join(spec[:text].split.map { |word| tag.span(word) }, " ")
    end

    def reveal_group(key)
      "textfx-#{key.to_s.tr("_", "-")}"
    end

    private

    def resolve_reveal_start(spec)
      base = spec[:start].is_a?(Symbol) ? beat_frame(spec[:start]) : spec[:start]
      base + spec[:offset]
    end

    def reveal_word_style(spec, key, index)
      if spec[:kind] == :punch
        "display:inline-block; opacity: var(--#{key}-w#{index}-op, 0); " \
          "transform: scale(var(--#{key}-w#{index}-sc, 1.3));"
      else
        "display:inline-block; opacity: var(--#{key}-w#{index}-op, 0); " \
          "transform: translateY(var(--#{key}-w#{index}-y, #{spec[:rise]}px));"
      end
    end
  end
end
