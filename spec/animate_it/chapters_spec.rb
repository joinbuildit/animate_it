require "rails_helper"

RSpec.describe AnimateIt::Chapters do
  def composition(&block)
    Class.new(AnimateIt::Composition) do
      fps 10
      duration 30.frames
      class_eval(&block)
    end
  end

  it "declares navigable chapters from existing beats" do
    target = composition do
      beat :intro, at: 0, length: 10.frames
      beat :finish, at: 15.frames, length: 15.frames
      chapter :intro, beat: :intro, label: "Intro", metadata: { thumbnail: "/intro.webp" }
      chapter :finish, beat: :finish, label: "Finish"
    end

    expect(target.chapters.map(&:name)).to eq(%i[intro finish])
    expect(target.chapters.fetch(:intro).metadata).to eq(thumbnail: "/intro.webp")
    expect(target.player_manifest.as_json.fetch("chapters").first).to include(
      "name" => "intro", "startFrame" => 0, "durationFrames" => 10,
      "metadata" => { thumbnail: "/intro.webp" }
    )
  end

  it "allows gaps while preserving ordered, non-overlapping chapters" do
    target = composition do
      beat :first, at: 0, length: 5.frames
      beat :second, at: 10.frames, length: 5.frames
      chapter :first, beat: :first, label: "First"
      chapter :second, beat: :second, label: "Second"
    end

    expect { target.chapters.validate! }.not_to raise_error
  end

  it "rejects missing beats, blank labels, duplicate names, overlap, and out-of-bounds chapters" do
    expect do
      composition { chapter :missing, beat: :missing, label: "Missing" }
    end.to raise_error(AnimateIt::Error, /Unknown beat/)

    expect do
      composition do
        beat :intro, at: 0, length: 5.frames
        chapter :intro, beat: :intro, label: " "
      end
    end.to raise_error(ArgumentError, /labels must not be blank/)

    expect do
      composition do
        beat :one, at: 0, length: 10.frames
        beat :two, at: 10.frames, length: 10.frames
        chapter :same, beat: :one, label: "One"
        chapter :same, beat: :two, label: "Two"
      end
    end.to raise_error(ArgumentError, /names must be unique/)

    expect do
      composition do
        beat :one, at: 0, length: 12.frames
        beat :two, at: 10.frames, length: 10.frames
        chapter :one, beat: :one, label: "One"
        chapter :two, beat: :two, label: "Two"
      end
    end.to raise_error(ArgumentError, /must not overlap/)

    expect do
      composition do
        beat :late, at: 25.frames, length: 10.frames
        chapter :late, beat: :late, label: "Late"
      end
    end.to raise_error(ArgumentError, /must fit within/)
  end
end
