module AnimateIt
  class Composition
    SUPPORTED_OUTPUT_FORMATS = %i[webm mp4 mov gif png_sequence png].freeze

    class << self
      attr_reader :timeline, :props_schema, :width, :height, :duration_in_frames

      def inherited(subclass)
        subclass.instance_variable_set(:@timeline, Timeline.new)
        subclass.instance_variable_set(:@props_schema, PropsSchema.new)
        subclass.instance_variable_set(:@fps, 30)
        subclass.instance_variable_set(:@width, 1920)
        subclass.instance_variable_set(:@height, 1080)
        subclass.instance_variable_set(:@zoom, 1.0)
        subclass.instance_variable_set(:@duration_in_frames, 30)
        subclass.instance_variable_set(:@output_format, :webm)
        subclass.instance_variable_set(:@verification_props, [{}].freeze)
        subclass.instance_variable_set(:@public_player_options, nil)
        subclass.instance_variable_set(:@servo_compatible, false)
        subclass.instance_variable_set(:@chapters, Chapters.new(subclass))
        super
      end

      def output_format(value = nil)
        return @output_format if value.nil?

        unless SUPPORTED_OUTPUT_FORMATS.include?(value)
          raise ArgumentError,
                "Unsupported output_format #{value.inspect} — pick :webm, :mp4, :mov, :gif, :png_sequence, or :png"
        end

        @output_format = value
      end

      def transparent?
        %i[webm mov gif png_sequence png].include?(output_format)
      end

      # Declarative outputs: list every (format, path) target this composition
      # should produce. Without a block, returns the registered outputs (empty
      # array if none have been declared).
      #
      #   outputs do
      #     mp4 to: "app/assets/images/pages/product/screener-hero.mp4"
      #     gif to: "app/assets/images/pages/product/screener-hero.gif"
      #     png to: "app/assets/images/pages/product/screener-hero-first.png", frame: 0
      #   end
      #
      # Paths are repo-relative; the renderer joins them onto Rails.root.
      def outputs(&block)
        @outputs ||= []
        return @outputs unless block

        builder = OutputsBuilder.new(assets_dir: assets_dir, basename: output_basename)
        builder.instance_eval(&block)
        @outputs = builder.outputs.freeze
        # Keep `output_format` in sync with the first animated output so single-
        # output legacy callers (bin/render_animate_it_video, AnimateIt Studio)
        # see a sensible format without re-declaring it.
        primary = @outputs.find { |o| o.frame.nil? }
        @output_format = primary.format if primary
        @outputs
      end

      def id(value = nil)
        return @id if value.nil?

        @id = value.to_s
        AnimateIt.register(self)
      end

      # Opt in to the seekable browser runtime. Legacy compositions continue
      # rendering individual frames on the server.
      def client_driven!
        @client_driven = true
      end

      def client_driven?
        @client_driven == true
      end

      # Marks a client-driven composition as eligible for the experimental
      # Servo capture backend. Servo renders the same player document as
      # Chromium; it does not interpret composition tracks independently.
      def servo_compatible!
        raise ArgumentError, "servo_compatible! requires client_driven!" unless client_driven?

        @servo_compatible = true
      end

      def servo_compatible?
        @servo_compatible == true
      end

      # Explicitly expose this composition through the production-safe public
      # player endpoint. Studio, frame, filmstrip, props, and render endpoints
      # remain local-only. Public playback always uses schema-default props.
      def public_player!(autoplay: false, loop: true)
        client_driven!
        @public_player_options = { autoplay: autoplay == true, loop: loop == true }.freeze
      end

      def public_player?
        @public_player_options.present?
      end

      def public_player_options
        @public_player_options || { autoplay: false, loop: true }.freeze
      end

      def verification_props(*variants)
        return @verification_props if variants.empty?

        raise ArgumentError, "verification_props entries must be hashes" unless variants.all?(Hash)

        @verification_props = variants.map(&:deep_symbolize_keys).freeze
      end

      def structure_epochs(*frames)
        return @structure_epochs || [] if frames.empty?

        @structure_epochs = frames.map(&:to_i).sort.uniq
      end

      def structure_layers
        timeline.segments.each_with_index.flat_map do |segment, segment_index|
          next [] unless segment.kind == :scene

          segment_end = segment.duration_frames ? segment.from_frame + segment.duration_frames : duration_in_frames
          epochs = structure_epochs.select { |frame| frame > segment.from_frame && frame < segment_end }
          bounds = ([segment.from_frame] + epochs).sort.uniq
          bounds.each_with_index.map do |from_frame, index|
            Tracks::Layer.new(
              segment:,
              segment_index:,
              from_frame:,
              to_frame: bounds[index + 1] || segment_end
            )
          end
        end
      end

      def render_structure(view_context, props: {})
        resolved_props = props_schema.resolve(props)
        rendered_layers = structure_layers.map do |layer|
          context = frame_context(frame: layer.from_frame, props: resolved_props, segment: layer.segment)
          view_context.tag.div(
            render_segment(view_context, layer.segment, context),
            class: "animate-it-layer",
            data: { animate_layer: layer.key }
          )
        end
        view_context.safe_join(rendered_layers)
      end

      def track_document(props: {})
        Tracks::Recorder.new(self, props:).call
      end

      def fps(value = nil)
        return @fps if value.nil?

        @fps = value.to_i
      end

      def size(width, height)
        @width = width.to_i
        @height = height.to_i
      end

      # Browser-side magnification applied via CSS `zoom` on `<body>` in the
      # frame layout. Multiplies every visual length (font sizes, padding,
      # widths) without changing the output viewport, so heros built against
      # px-sized host partials can lift up the apparent scale without
      # rewriting CSS. Default `1.0` (no zoom).
      #
      #   size 1080, 1170
      #   zoom 1.1
      #
      # The viewport stays at `size(...)`; only the rendered content inside
      # `<body>` is magnified. Combine `zoom` with a smaller `size` to "zoom
      # in" the apparent scale of the composition at the same aspect ratio.
      def zoom(value = nil)
        return @zoom if value.nil?

        @zoom = value.to_f
      end

      def duration(value = nil)
        return @duration_in_frames if value.nil?

        @duration_in_frames = Units.frames(value, fps:)
      end

      def props(&block)
        props_schema.instance_eval(&block) if block
        props_schema
      end

      # ----- Beats: named time markers on the composition timeline ------
      def beat(name, at:, length:)
        beats.add(name, at: at, length: length)
      end

      def beats
        @beats ||= Beats.new(fps: fps)
      end

      # Public, user-navigable moments. Chapters reference existing beats so
      # animation timing stays the single source of truth.
      def chapter(name, beat:, label:, metadata: {})
        chapters.add(name, beat:, label:, metadata:)
      end

      def chapters
        @chapters ||= Chapters.new(self)
      end

      def player_manifest
        PlayerManifest.new(self)
      end

      # ----- Outputs path helpers --------------------------------------
      # Declare a directory + basename so `outputs do ... end` entries can
      # be specified by format alone:
      #
      #   assets_dir "app/assets/images/pages/product"
      #   output_basename "screener-hero"
      #
      #   outputs do
      #     mp4
      #     webm
      #     gif
      #     png frame: 0       # → screener-hero-first.png
      #   end
      def assets_dir(value = nil)
        @assets_dir = value.to_s if value
        @assets_dir
      end

      def output_basename(value = nil)
        @output_basename = value.to_s if value
        @output_basename || @id
      end

      # ----- Audio DSL --------------------------------------------------
      # Loop a track for the full duration (or a slice). Background music.
      def audio_loop(path, duration: nil, from: 0, name: nil, gain: 1.0, track: :background)
        length = duration || (@duration_in_frames - Units.frames(from, fps: fps))
        audio(
          path,
          duration: length,
          from:,
          name: name || "loop-#{File.basename(path.to_s)}",
          track:,
          gain:,
          loop: true
        )
      end

      # Play a voice-over clip at a named beat (or time/frame). The clip's
      # duration defaults to the beat's length.
      def voice_over(path, at:, duration: nil, name: nil, gain: 1.0, track: :voice)
        beat = at.is_a?(Symbol) ? beats.fetch(at) : nil
        from = beat ? beat.start_frame : at
        length = duration || (beat ? beat.duration_frames : 1.second)
        audio(path, duration: length, from: from, name: name || File.basename(path.to_s), track: track, gain: gain)
      end

      def sequence(
        from: 0,
        start_at: nil,
        duration: nil,
        name: nil,
        scene: nil,
        layout: :none,
        class_name: nil,
        style: nil,
        show_in_timeline: true,
        track: :main,
        &block
      )
        timeline.add_segment(
          name: name || scene&.name || "sequence-#{timeline.segments.size + 1}",
          from_frame: Units.frames(start_at || from, fps:),
          duration_frames: Units.frames(duration, fps:),
          scene_class: scene,
          renderer: block,
          layout:,
          class_name:,
          style:,
          show_in_timeline:,
          track:
        )
      end

      def scene(scene_class, duration: nil, from: 0, start_at: nil, name: nil, **)
        # Tell the scene class which composition it belongs to so its
        # animation property procs can resolve symbolic beat names against
        # the composition's beat registry.
        scene_class.composition_class = self if scene_class.respond_to?(:composition_class=)
        # If duration isn't given, default to the full composition duration
        # (single-scene shorthand support).
        duration ||= @duration_in_frames
        sequence(from:, start_at:, duration:, name:, scene: scene_class, **)
      end

      # Sweep nested AnimateIt::Scene subclasses and auto-mount the single
      # scene if no explicit `scene` / `series` was declared. Called by the
      # registrar after composition file load.
      def auto_mount_single_scene!
        return if timeline.segments.any?

        nested = constants.map { |c| const_get(c) }.select do |const|
          const.is_a?(Class) && const < AnimateIt::Scene
        end
        return unless nested.size == 1

        scene(nested.first)
      end

      # Place an audio segment on its own track. The renderer doesn't draw
      # audio; the studio plays it via <audio> tags synced to the scrubber, and
      # ffmpeg muxes it into the final encode.
      def audio(path, duration: nil, from: 0, start_at: nil, name: nil, track: :audio, gain: 1.0, loop: false)
        begin
          gain = Float(gain)
        rescue TypeError, ArgumentError
          raise ArgumentError, "Audio gain must be a number between 0.0 and 1.0"
        end
        raise ArgumentError, "Audio gain must be between 0.0 and 1.0" unless gain.between?(0.0, 1.0)

        timeline.add_segment(
          name: name || File.basename(path.to_s),
          from_frame: Units.frames(start_at || from, fps:),
          duration_frames: Units.frames(duration, fps:),
          kind: :audio,
          track:,
          source: { path: path.to_s, gain:, loop: },
          show_in_timeline: true
        )
      end

      def series(&)
        SeriesBuilder.new(self).instance_eval(&)
      end

      def transition_series(&)
        TransitionSeriesBuilder.new(self).instance_eval(&)
      end

      def frame_context(frame:, props:, segment: nil)
        FrameContext.new(
          self,
          props_schema.resolve(props),
          frame.to_i,
          segment ? segment.local_frame(frame.to_i) : frame.to_i,
          fps,
          duration_in_frames,
          width,
          height,
          segment
        )
      end

      def render_frame(view_context, frame:, props: {}, segment_origins: false)
        resolved_props = props_schema.resolve(props)
        segments = timeline.active_segments(frame.to_i, kind: :scene)
        return "" if segments.empty?

        rendered_segments = segments.map do |segment|
          context = frame_context(frame:, props: resolved_props, segment:)
          content = render_segment(view_context, segment, context)
          next content unless segment_origins

          view_context.tag.div(content, data: { animate_it_segment_origin: segment.from_frame })
        end
        view_context.safe_join(rendered_segments)
      end

      private

      def render_segment(view_context, segment, context)
        return "" if segment.kind == :transition

        content = if segment.scene_class
                    segment.scene_class.new(context:, props: context.props).render(view_context)
                  else
                    view_context.capture(context, context.props, &segment.renderer)
                  end

        return content unless segment.layout == :absolute_fill

        view_context.tag.div(
          content,
          class: ["animate-it-absolute-fill", segment.class_name].compact,
          style: Style.build(
            "position: absolute",
            "inset: 0",
            "width: 100%",
            "height: 100%",
            "display: flex",
            "flex-direction: column",
            segment.style
          )
        )
      end
    end

    class SeriesBuilder
      def initialize(composition)
        @composition = composition
        @cursor = 0
      end

      def scene(scene_class, duration:, after: 0, start_at: nil, name: nil, **)
        duration_frames = Units.frames(duration, fps: @composition.fps)
        from_frame = if start_at
                       Units.frames(start_at, fps: @composition.fps)
                     else
                       @cursor + Units.frames(after, fps: @composition.fps)
                     end

        @composition.scene(scene_class, from: from_frame, duration: duration_frames.frames, name:, **)
        @cursor = from_frame + duration_frames
      end

      def audio(path, duration: nil, after: 0, start_at: nil, name: nil, track: :audio, gain: 1.0)
        from_frame = if start_at
                       Units.frames(start_at, fps: @composition.fps)
                     else
                       @cursor + Units.frames(after, fps: @composition.fps)
                     end

        @composition.audio(path, duration:, from: from_frame, name:, track:, gain:)
      end

      def transition(_name, duration:)
        @cursor -= Units.frames(duration, fps: @composition.fps)
      end
    end

    class TransitionSeriesBuilder
      def initialize(composition)
        @composition = composition
        @cursor = 0
      end

      def scene(scene_class, duration:, name: nil, **)
        duration_frames = Units.frames(duration, fps: @composition.fps)
        @composition.scene(scene_class, from: @cursor, duration: duration_frames.frames, name:, **)
        @cursor += duration_frames
      end

      def transition(name, duration:)
        @cursor -= Units.frames(duration, fps: @composition.fps)
        @composition.timeline.add_segment(
          name: "#{name}-transition",
          from_frame: @cursor,
          duration_frames: Units.frames(duration, fps: @composition.fps),
          kind: :transition,
          transition: name,
          show_in_timeline: true
        )
      end

      def overlay(scene_class, duration:, offset: 0, name: nil, **)
        from_frame = @cursor - (Units.frames(duration,
                                             fps: @composition.fps) / 2) + Units.frames(offset, fps: @composition.fps)
        @composition.scene(scene_class, from: from_frame, duration:, name:, **)
      end
    end
  end
end
