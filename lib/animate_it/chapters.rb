require "json"

module AnimateIt
  Chapter = Data.define(:name, :label, :beat_name, :start_frame, :duration_frames, :metadata) do
    def end_frame
      start_frame + duration_frames
    end

    def as_json(*)
      {
        "name" => name.to_s,
        "label" => label,
        "beat" => beat_name.to_s,
        "startFrame" => start_frame,
        "durationFrames" => duration_frames,
        "endFrame" => end_frame,
        "metadata" => metadata
      }
    end
  end

  class Chapters
    include Enumerable

    def initialize(composition)
      @composition = composition
      @chapters = []
    end

    def add(name, beat:, label:, metadata: {})
      key = name.to_sym
      raise ArgumentError, "AnimateIt chapter names must be unique: #{name.inspect}" if @chapters.any? { |chapter| chapter.name == key }
      raise ArgumentError, "AnimateIt chapter labels must not be blank" if label.to_s.strip.empty?
      raise ArgumentError, "AnimateIt chapter metadata must be a hash" unless metadata.is_a?(Hash)

      JSON.generate(metadata)

      beat_record = @composition.beats.fetch(beat)
      chapter = Chapter.new(
        name: key,
        label: label.to_s,
        beat_name: beat_record.name,
        start_frame: beat_record.start_frame,
        duration_frames: beat_record.duration_frames,
        metadata: metadata.freeze
      )
      validate_after!(@chapters.last, chapter)
      validate_bounds!(chapter)
      @chapters << chapter
      chapter
    end

    def fetch(name)
      @chapters.find { |chapter| chapter.name == name.to_sym } ||
        raise(Error, "Unknown chapter: #{name.inspect}. Declared: #{@chapters.map(&:name).inspect}")
    end

    def each(&)
      @chapters.each(&)
    end

    delegate :empty?, to: :@chapters

    def as_json(*)
      validate!
      @chapters.map(&:as_json)
    end

    def validate!
      @chapters.each_with_index do |chapter, index|
        validate_after!(@chapters[index - 1], chapter) if index.positive?
        validate_bounds!(chapter)
      end
      self
    end

    private

    def validate_after!(previous, chapter)
      return unless previous

      raise ArgumentError, "AnimateIt chapters must have strictly increasing start frames" if chapter.start_frame <= previous.start_frame
      return if chapter.start_frame >= previous.end_frame

      raise ArgumentError, "AnimateIt chapters must not overlap: #{previous.name.inspect} and #{chapter.name.inspect}"
    end

    def validate_bounds!(chapter)
      return if chapter.start_frame >= 0 && chapter.duration_frames.positive? && chapter.end_frame <= @composition.duration_in_frames

      raise ArgumentError,
            "AnimateIt chapter #{chapter.name.inspect} must fit within 0...#{@composition.duration_in_frames} frames"
    end
  end
end
