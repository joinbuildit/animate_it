require "json"

module AnimateIt
  module Tracks
    # Serializable track document consumed by the client runtime.
    class Document
      attr_reader :fps, :duration

      def initialize(fps:, duration:)
        @fps = fps
        @duration = duration
        @samples = Hash.new { |hash, group| hash[group] = {} }
        @keyframes = Hash.new { |hash, group| hash[group] = {} }
        @text_samples = {}
        @group_selectors = {}
        @text_selectors = {}
        @layers = []
      end

      def record_sample(group, var, frame, value, selector: nil)
        @group_selectors[group.to_s] = selector if selector
        track = @samples[group.to_s][normalize_var(var)] ||= Array.new(duration)
        track[frame] = value&.to_s
      end

      def add_keyframe_track(group, var, frames:, values:, easing: :ease_out, unit: nil, selector: nil)
        @group_selectors[group.to_s] = selector if selector
        @keyframes[group.to_s][normalize_var(var)] = {
          "t" => "kf",
          "k" => frames.map(&:to_i).zip(values),
          "e" => easing.to_s,
          "u" => unit.to_s
        }
      end

      def record_text(key, frame, value, selector: nil)
        @text_selectors[key.to_s] = selector if selector
        track = @text_samples[key.to_s] ||= Array.new(duration)
        track[frame] = value.to_s
      end

      def add_layer(key, from_frame, to_frame, origin_frame:)
        @layers << {
          "sel" => %([data-animate-layer="#{key}"]),
          "from" => from_frame,
          "to" => to_frame,
          "origin" => origin_frame
        }
      end

      def as_json
        groups = @samples.transform_values { |vars| vars.transform_values { |track| rle(track) } }
        @keyframes.each { |group, vars| (groups[group] ||= {}).merge!(vars) }

        {
          "v" => 2,
          "fps" => fps,
          "duration" => duration,
          "groups" => groups,
          "groupSelectors" => @group_selectors,
          "texts" => @text_samples.transform_values { |track| rle(fill(track)) },
          "textSelectors" => @text_selectors,
          "layers" => @layers
        }
      end

      def to_json(*)
        JSON.generate(as_json)
      end

      private

      def normalize_var(var)
        name = var.to_s.tr("_", "-")
        name.start_with?("--") ? name : "--#{name}"
      end

      # Text values hold across inactive gaps. CSS variable gaps stay nil so
      # the browser can remove a property instead of leaking an earlier value.
      def fill(track)
        last = nil
        forward = track.map { |value| last = value || last }
        first = forward.find { |value| value } || ""
        forward.map { |value| value || first }
      end

      def rle(track)
        runs = []
        track.each do |value|
          if runs.any? && runs.last[0] == value
            runs.last[1] += 1
          else
            runs << [value, 1]
          end
        end
        { "t" => "rle", "r" => runs }
      end
    end
  end
end
