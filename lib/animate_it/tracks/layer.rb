module AnimateIt
  module Tracks
    # One structural slice of a composition: a scene segment's DOM rendered
    # at `from_frame`, shown by the client runtime for frames in
    # [from_frame, to_frame). Layers are the union of timeline-segment
    # windows and `structure_epochs` boundaries.
    Layer = Data.define(:segment, :segment_index, :from_frame, :to_frame) do
      def key
        "s#{segment_index}/e#{from_frame}"
      end
    end
  end
end
