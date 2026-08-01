module AnimateIt
  module Tracks
    # Samples declared variable/text tracks and serializes compact keyframes.
    class Recorder
      ANIMATE_GROUP = "animate".freeze

      def initialize(composition, props: {})
        @composition = composition
        @props = composition.props_schema.resolve(props)
        @scene_segments = composition.timeline.segments.each_with_index.filter_map do |segment, index|
          [segment, index] if segment.kind == :scene
        end
        @layers_by_segment = composition.structure_layers.group_by(&:segment_index)
      end

      def call
        document = Document.new(fps: @composition.fps, duration: @composition.duration_in_frames)
        @composition.structure_layers.each do |layer|
          document.add_layer(layer.key, layer.from_frame, layer.to_frame, origin_frame: layer.segment.from_frame)
        end
        record_animate_dsl(document)
        record_word_reveals(document)
        record_samples(document)
        document
      end

      private

      def record_samples(document)
        @composition.duration_in_frames.times do |frame|
          @scene_segments.each do |segment, segment_index|
            next unless segment.active_at?(frame)

            scene_class = segment.scene_class
            next unless scene_class
            next if scene_class.var_groups.empty? && scene_class.text_tracks.empty?

            scene = build_scene(segment, frame)
            record_frame_vars(document, scene, segment_index, frame)
            record_frame_texts(document, scene, segment_index, frame)
          end
        end
      end

      def record_frame_vars(document, scene, segment_index, frame)
        scene.class.var_groups.each_key do |group|
          vars = evaluate(scene, "track_vars :#{group}", frame) { scene.evaluate_var_group(group) }
          vars.each do |var, value|
            document.record_sample(
              binding_key(segment_index, group), var, frame, value,
              selector: group_selector(segment_index, group)
            )
          end
        end
      end

      def record_frame_texts(document, scene, segment_index, frame)
        scene.class.text_tracks.each_key do |key|
          value = evaluate(scene, "text_track :#{key}", frame) { scene.evaluate_text_track(key) }
          document.record_text(
            binding_key(segment_index, key), frame, value,
            selector: text_selector(segment_index, key)
          )
        end
      end

      def record_animate_dsl(document)
        @scene_segments.each do |segment, segment_index|
          scene_class = segment.scene_class
          next unless scene_class
          next if scene_class.animations.elements.empty?

          scene = build_scene(segment, segment.from_frame)
          scene_class.animations.elements.each_value do |element|
            element.properties.each do |prop|
              keyframes = prop.keyframes_to_values.call(scene)
              document.add_keyframe_track(
                binding_key(segment_index, ANIMATE_GROUP),
                prop.var_name(element.name),
                frames: global_frames(segment, keyframes.keys),
                values: keyframes.values,
                unit: prop.unit,
                selector: group_selector(segment_index, ANIMATE_GROUP)
              )
            end
          end
        end
      end

      def record_word_reveals(document)
        @scene_segments.each do |segment, segment_index|
          scene_class = segment.scene_class
          next unless scene_class
          next if scene_class.word_reveals_registry.empty?

          scene = build_scene(segment, segment.from_frame)
          scene_class.word_reveals_registry.each_key do |key|
            scene.word_reveal_tracks(key).each do |track|
              document.add_keyframe_track(
                binding_key(segment_index, scene.reveal_group(key)),
                track[:var],
                frames: global_frames(segment, track[:frames]),
                values: track[:values],
                unit: track[:unit],
                selector: group_selector(segment_index, scene.reveal_group(key))
              )
            end
          end
        end
      end

      def build_scene(segment, frame)
        context = @composition.frame_context(frame:, props: @props, segment:)
        segment.scene_class.current_frame = context.local_frame
        segment.scene_class.new(context:, props: context.props)
      end

      def binding_key(segment_index, name)
        "s#{segment_index}:#{name}"
      end

      def group_selector(segment_index, group)
        layer_descendant_selector(segment_index, %([data-animate-vars="#{group}"]))
      end

      def text_selector(segment_index, key)
        layer_descendant_selector(segment_index, %([data-animate-text="#{key}"]))
      end

      def layer_descendant_selector(segment_index, descendant)
        @layers_by_segment.fetch(segment_index).map do |layer|
          %([data-animate-layer="#{layer.key}"] #{descendant})
        end.join(",")
      end

      def global_frames(segment, frames)
        frames.map { |frame| segment.from_frame + frame }
      end

      def evaluate(scene, label, frame)
        yield
      rescue NoMethodError => e
        raise Error, "#{label} on #{scene.class} raised at frame #{frame}: #{e.message}. " \
                     "Track blocks run without a view context — keep them to pure var math " \
                     "and move rendering concerns into the template."
      end
    end
  end
end
