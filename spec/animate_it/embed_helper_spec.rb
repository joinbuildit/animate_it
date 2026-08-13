require "rails_helper"

RSpec.describe AnimateIt::EmbedHelper, type: :helper do
  before do
    AnimateIt.register(ClientRuntimeSpecVideo)
    AnimateIt.register(DummyMotionVideo)
  end

  it "builds a responsive iframe for an allowlisted composition" do
    html = helper.animate_it_player("client-runtime-spec", title: "Product demo")

    expect(html).to include('src="/animate_it/public/compositions/client-runtime-spec/player"')
    expect(html).to include('title="Product demo"')
    expect(html).to include('allow="autoplay; fullscreen"')
    expect(html).to include("aspect-ratio:240/120")
  end

  it "refuses to embed a composition that has not opted in" do
    expect { helper.animate_it_player("dummy-motion") }
      .to raise_error(ArgumentError, /not public/)
  end

  it "builds a poster-first interactive embed with accessible pill chapters" do
    html = helper.animate_it_embed(
      "client-runtime-spec",
      poster: "/poster.webp",
      navigation: { preset: :pills, mobile: :carousel },
      title: "Product walkthrough"
    )
    page = Capybara.string(html)
    embed = page.find("animate-it-embed", visible: :all)
    manifest = JSON.parse(embed.find("script[data-animate-it-embed-manifest]", visible: :all).text)

    expect(page).to have_css('link[data-animate-it-embed-asset="style"]', visible: :all)
    expect(page).to have_css('script[data-animate-it-embed-asset="script"]', visible: :all)
    expect(page).to have_css(".animate-it-chapters--mobile-carousel", visible: :all)
    expect(page).to have_css('button[aria-label="Jump to Intro"]', visible: :all)
    expect(page).to have_css('svg rect[pathlength="1"]', count: 3, visible: :all)
    expect(page).to have_css('img[src="/poster.webp"]', visible: :all)
    expect(manifest.dig("options", "loadWhenVisible")).to eq(0.25)
    expect(manifest.dig("options", "playWhenVisible")).to eq(2.0 / 3)
    expect(manifest.dig("variants", 0, "composition", "chapters").pluck("name"))
      .to eq(%w[intro details finish])
  end

  it "supports headless custom chapter controls" do
    html = helper.animate_it_embed("client-runtime-spec", poster: "/poster.webp") do |embed|
      embed.chapter_navigation(class: "custom-timeline") do |chapter|
        chapter.button(class: "product-demo-card") do
          helper.safe_join([helper.tag.span(chapter.label), helper.tag.span(chapter.thumbnail.to_s)])
        end
      end
    end
    page = Capybara.string(html)

    expect(page).to have_css("nav.custom-timeline .product-demo-card", count: 3, visible: :all)
    expect(page).to have_css('[data-animate-it-chapter="intro"]', text: "Intro/intro.webp", visible: :all)
    expect(page).to have_no_css(".animate-it-chapters--pills", visible: :all)
    expect(page).to have_no_css(".animate-it-chapter--pills", visible: :all)
  end

  it "renders deterministic canvas chapter controls for Studio and exports" do
    html = helper.animate_it_chapter_navigation(
      composition: ClientRuntimeSpecVideo,
      preset: :pills,
      hide_when_embedded: true
    )
    page = Capybara.string(html)

    expect(page).to have_css("style[data-animate-it-chapter-styles]", visible: :all)
    expect(page).to have_css('[data-animate-it-hide-when-embedded="true"]', visible: :all)
    expect(page).to have_css('div[data-animate-it-chapter="intro"]', visible: :all)
    expect(page).to have_no_css("button", visible: :all)
  end

  it "renders headless canvas SVG without applying the pill preset" do
    html = helper.animate_it_chapter_navigation(composition: ClientRuntimeSpecVideo, frame: 5) do |chapter|
      chapter.element(tag: :svg, class: "timeline-marker", viewBox: "0 0 20 20") do
        helper.tag.text(chapter.label, x: 1, y: 10)
      end
    end
    page = Capybara.string(html)

    expect(page).to have_css("svg.timeline-marker", count: 3, visible: :all)
    expect(page).to have_css('[data-animate-it-chapter="details"][data-chapter-state="current"]', visible: :all)
    expect(page).to have_no_css(".animate-it-chapter--pills", visible: :all)
  end

  it "ships perimeter progress as one SVG stroke with an outer CSS glow" do
    css = AnimateIt::EmbedStyles.chapter_source

    expect(css).to include("stroke-dasharray: var(--animate-it-chapter-progress) 1")
    expect(css).to include("stroke-opacity: clamp")
    expect(css).to include("box-shadow: var(--animate-it-active-glow)")
    expect(css).not_to include("filter: blur")
    expect(css).to include("--animate-it-chapter-font", "--animate-it-carousel-distance")
  end

  it "rejects invalid embed options before rendering" do
    expect do
      helper.animate_it_embed("client-runtime-spec", poster: "/poster.webp", load_when_visible: 1.1)
    end.to raise_error(ArgumentError, /thresholds must be between 0 and 1/)

    expect do
      helper.animate_it_embed("client-runtime-spec", poster: "/poster.webp", reduced_motion: nil)
    end.to raise_error(ArgumentError, /reduced_motion must be :poster/)
  end

  it "validates responsive chapter compatibility and emits picture sources" do
    responsive = Class.new(AnimateIt::Composition) do
      id "client-runtime-mobile"
      public_player!
      fps 10
      size 120, 240
      duration 24.frames
      beat :intro, at: 0, length: 8.frames
      beat :details, at: 8.frames, length: 8.frames
      beat :finish, at: 16.frames, length: 8.frames
      chapter :intro, beat: :intro, label: "Intro"
      chapter :details, beat: :details, label: "Details"
      chapter :finish, beat: :finish, label: "Finish"
    end
    AnimateIt.register(responsive)

    html = helper.animate_it_embed(
      "client-runtime-spec",
      poster: "/desktop.webp",
      variants: [{ media: "(max-width: 767px)", composition: "client-runtime-mobile", poster: "/mobile.webp" }]
    )
    page = Capybara.string(html)

    expect(page).to have_css('source[media="(max-width: 767px)"][srcset="/mobile.webp"]', visible: :all)
  ensure
    AnimateIt.reset!
  end

  it "rejects responsive variants with different chapter contracts" do
    mismatched = Class.new(AnimateIt::Composition) do
      id "client-runtime-mismatch"
      public_player!
      duration 18.frames
      beat :intro, at: 0, length: 18.frames
      chapter :intro, beat: :intro, label: "Different"
    end
    AnimateIt.register(mismatched)

    expect do
      helper.animate_it_embed(
        "client-runtime-spec",
        poster: "/desktop.webp",
        variants: [{ media: "(max-width: 767px)", composition: "client-runtime-mismatch", poster: "/mobile.webp" }]
      )
    end.to raise_error(ArgumentError, /same ordered chapter names and labels/)
  ensure
    AnimateIt.reset!
  end
end
