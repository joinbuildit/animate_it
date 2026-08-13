module AnimateIt
  class ChapterPresenter
    attr_reader :chapter

    delegate :name, :label, :start_frame, :duration_frames, :end_frame, :metadata, to: :chapter

    def initialize(view, chapter, interactive:, state:)
      @view = view
      @chapter = chapter
      @interactive = interactive
      @state = state
    end

    def thumbnail
      metadata[:thumbnail] || metadata["thumbnail"]
    end

    def button(content = nil, **attributes, &block)
      body = block ? @view.capture(self, &block) : (content || label)
      classes = ["animate-it-chapter", attributes.delete(:class)].compact.join(" ")
      attributes, data = stateful_attributes(attributes)
      attributes[:type] ||= "button"
      attributes[:"aria-label"] ||= "Jump to #{label}"
      @view.tag.button(body, **attributes, class: classes, data:)
    end

    def element(content = nil, tag: :div, **attributes, &block)
      body = block ? @view.capture(self, &block) : (content || label)
      classes = ["animate-it-chapter", attributes.delete(:class)].compact.join(" ")
      attributes, data = stateful_attributes(attributes)
      @view.tag.public_send(tag, body, **attributes, class: classes, data:)
    end

    def default_control(preset: :pills)
      progress = @view.tag.svg(
        @view.tag.rect(x: 1, y: 1, width: 98, height: 38, rx: 19, pathLength: 1),
        class: "animate-it-chapter__progress", viewBox: "0 0 100 40", preserveAspectRatio: "none", aria: { hidden: true }
      )
      body = @view.safe_join([progress, @view.tag.span(label, class: "animate-it-chapter__label")])
      classes = "animate-it-chapter animate-it-chapter--#{preset}"
      if @interactive
        button(body, class: classes.delete_prefix("animate-it-chapter "))
      else
        element(body, class: classes.delete_prefix("animate-it-chapter "))
      end
    end

    private

    def stateful_attributes(attributes)
      attributes = attributes.dup
      data = (attributes.delete(:data) || {}).merge(
        animate_it_chapter: name,
        chapter_state: @state.fetch(:state),
        chapter_position: @state.fetch(:position)
      )
      variables = [
        "--animate-it-chapter-progress: #{@state.fetch(:progress)}",
        "--animate-it-chapter-active: #{@state.fetch(:active)}",
        "--animate-it-chapter-complete: #{@state.fetch(:complete)}",
        attributes.delete(:style)
      ].compact.join(";")
      attributes[:style] = variables
      attributes[:"aria-current"] = "step" if @interactive && @state.fetch(:state) == "current"
      [attributes, data]
    end
  end

  class ChapterNavigationBuilder
    def initialize(view, composition, interactive:, preset: :pills, mobile: nil, frame: 0)
      @view = view
      @composition = composition
      @interactive = interactive
      @preset = preset&.to_sym
      @mobile = mobile&.to_sym
      @frame = frame.to_i
    end

    def render(**attributes, &block)
      current_index = current_chapter_index
      chapters = @composition.chapters.each_with_index.map do |chapter, index|
        presenter = ChapterPresenter.new(@view, chapter, interactive: @interactive, state: chapter_state(chapter, index, current_index))
        block ? @view.capture(presenter, &block) : presenter.default_control(preset: @preset || :pills)
      end
      classes = ["animate-it-chapters", @preset && "animate-it-chapters--#{@preset}",
                 @mobile && "animate-it-chapters--mobile-#{@mobile}", attributes.delete(:class)].compact.join(" ")
      data = (attributes.delete(:data) || {}).merge(animate_it_chapter_navigation: true)
      attributes[:"aria-label"] ||= "Animation chapters" if @interactive
      tag = @interactive ? :nav : :div
      @view.tag.public_send(tag, @view.safe_join(chapters), **attributes, class: classes, data:)
    end

    private

    def current_chapter_index
      @composition.chapters.to_a.rindex { |chapter| @frame >= chapter.start_frame } || -1
    end

    def chapter_state(chapter, index, current_index)
      state = if current_index.negative? || index > current_index
                "upcoming"
              elsif index < current_index
                "completed"
              else
                "current"
              end
      progress = if state == "completed"
                   1.0
                 elsif state == "current"
                   chapter_progress(chapter)
                 else
                   0.0
                 end
      {
        state:,
        position: chapter_position(index, current_index),
        progress:,
        active: state == "current" ? 1 : 0,
        complete: state == "completed" ? 1 : 0
      }
    end

    def chapter_progress(chapter)
      return 1.0 if chapter.duration_frames == 1

      (@frame - chapter.start_frame).fdiv(chapter.duration_frames - 1).clamp(0, 1)
    end

    def chapter_position(index, current_index)
      return "hidden" if current_index.negative?
      return "current" if index == current_index
      return "previous" if index == current_index - 1
      return "next" if index == current_index + 1

      "hidden"
    end
  end

  module ChapterNavigationHelper
    def animate_it_chapter_navigation(
      composition: nil, preset: nil, mobile: nil, hide_when_embedded: false, frame: nil, **attributes, &
    )
      target = composition || instance_variable_get(:@composition)
      raise ArgumentError, "animate_it_chapter_navigation requires a composition" unless target

      target.chapters.validate!
      data = (attributes.delete(:data) || {}).merge(animate_it_hide_when_embedded: hide_when_embedded ? "true" : "false")
      attributes[:style] = ["--animate-it-chapter-count: #{target.chapters.count}", attributes[:style]].compact.join(";")
      builder = ChapterNavigationBuilder.new(
        self, target, interactive: false, preset:, mobile:, frame: frame || instance_variable_get(:@frame) || 0
      )
      safe_join(
        [
          tag.style(AnimateIt::EmbedStyles.chapter_source.html_safe, data: { animate_it_chapter_styles: true }),
          builder.render(**attributes, data:, &)
        ]
      )
    end
  end
end
