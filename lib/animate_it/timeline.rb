module AnimateIt
  class Timeline
    Segment = Data.define(
      :name,
      :from_frame,
      :duration_frames,
      :scene_class,
      :renderer,
      :layout,
      :class_name,
      :style,
      :show_in_timeline,
      :kind,
      :transition,
      :track,
      :source
    ) do
      def active_at?(frame)
        return frame >= from_frame if duration_frames.nil?

        frame >= from_frame && frame < from_frame + duration_frames
      end

      def local_frame(frame)
        frame - from_frame
      end
    end

    attr_reader :segments

    def initialize
      @segments = []
    end

    def add_segment(
      name:,
      from_frame:,
      duration_frames:,
      scene_class: nil,
      renderer: nil,
      layout: :none,
      class_name: nil,
      style: nil,
      show_in_timeline: true,
      kind: :scene,
      transition: nil,
      track: :main,
      source: nil
    )
      segments << Segment.new(
        name,
        from_frame,
        duration_frames,
        scene_class,
        renderer,
        layout,
        class_name,
        style,
        show_in_timeline,
        kind,
        transition,
        track,
        source
      )
    end

    def active_segments(frame, kind: nil)
      result = segments.select { |segment| segment.active_at?(frame) }
      kind ? result.select { |segment| segment.kind == kind } : result
    end

    # Tracks in declaration order — first time a segment names a track wins.
    def tracks
      segments.map(&:track).uniq
    end

    def segments_for_track(track)
      segments.select { |segment| segment.track == track }
    end
  end
end
