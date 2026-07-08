module AnimateIt
  # A named time marker on a Composition's timeline. Beats let you give
  # frame ranges meaningful names ("intro", "voice_note", "thinking") and
  # reference them from animations:
  #
  #   beat :voice_note, at: "5.5s", length: "0.67s"
  #   animate :step_2 do
  #     fade in: :voice_note
  #   end
  Beat = Data.define(:name, :start_frame, :duration_frames) do
    def end_frame
      start_frame + duration_frames
    end

    # Inclusive: `range.last` is the last frame the beat covers.
    def range
      start_frame..end_frame
    end

    def first_half
      half = duration_frames / 2
      start_frame..(start_frame + half)
    end

    def second_half
      half = duration_frames / 2
      (start_frame + half)..end_frame
    end
  end

  class Beats
    def initialize(fps:)
      @fps = fps
      @beats = {}
    end

    def add(name, at:, length:)
      @beats[name.to_sym] = Beat.new(
        name: name.to_sym,
        start_frame: AnimateIt::Units.frames(at, fps: @fps).to_i,
        duration_frames: AnimateIt::Units.frames(length, fps: @fps).to_i
      )
    end

    def fetch(name)
      @beats.fetch(name.to_sym) do
        raise Error, "Unknown beat: #{name.inspect}. Declared: #{@beats.keys.inspect}"
      end
    end

    def [](name)
      @beats[name.to_sym]
    end

    def all
      @beats.values
    end

    delegate :empty?, to: :@beats
  end
end
