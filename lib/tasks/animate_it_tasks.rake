require "json"

def animate_it_render_host
  # Prefer ANIMATE_IT_HOST; fall back to the legacy RAILS_MOTION_HOST, then
  # RAILS_HOST, then localhost.
  ENV["ANIMATE_IT_HOST"].presence ||
    ENV["RAILS_MOTION_HOST"].presence ||
    ENV["RAILS_HOST"].presence ||
    "http://127.0.0.1:3000"
end

namespace :animate_it do
  desc "Validate source assets and provenance required by AnimateIt compositions"
  task preflight: :environment do
    result = AnimateIt::AssetManifest.new.validate!
    puts "AnimateIt asset preflight passed (#{result.checked} assets)."
  end

  desc <<~DESC
    Render a single composition's declared outputs to their asset paths.

    Usage:
      bin/rails 'animate_it:render[<composition-id>]'
      bin/rails 'animate_it:render[<composition-id>,<start>..<end>]'   # render a subset of frames
      bin/rails 'animate_it:render[<composition-id>,<start>-<end>]'    # same, dash-separated

    When a frame range is given, animated outputs (mp4/webm/gif) are
    encoded from just those frames — the result is a clipped preview
    starting at frame <start>. Still PNG outputs still render at their
    declared `frame:` and are skipped if that frame is outside the range.
  DESC
  task :render, %i[id frames] => :environment do |_t, args|
    raise "Usage: bin/rails 'animate_it:render[<composition-id>,(<start>..<end>)?]'" if args[:id].blank?

    AnimateIt.load_compositions!
    composition = AnimateIt.registry.fetch(args[:id])
    host = animate_it_render_host
    frame_range = parse_frame_range(args[:frames], composition)
    puts "Rendering frames #{frame_range.first}..#{frame_range.last} of #{composition.duration_in_frames}" if frame_range
    written = AnimateIt::AssetRenderer.render_composition(
      composition, host: host, on_progress: progress_logger, frame_range: frame_range
    )
    puts ""
    written.compact.each { |path| puts "  → #{path.relative_path_from(Rails.root)}" }
  end

  desc "Render every registered composition's declared outputs"
  task render_all: :environment do
    AnimateIt.load_compositions!
    host = animate_it_render_host

    AnimateIt.compositions.each do |composition|
      next if composition.outputs.empty?

      label = "output#{"s" unless composition.outputs.size == 1}"
      puts "Rendering #{composition.id} (#{composition.outputs.size} #{label})"
      written = AnimateIt::AssetRenderer.render_composition(composition, host: host, on_progress: progress_logger)
      puts ""
      written.each { |path| puts "  → #{path.relative_path_from(Rails.root)}" }
    end
  end

  desc <<~DESC
    Pixel-diff a composition's client-driven /player page against the legacy
    /filmstrip. Samples every <step>-th frame (default 10; use 1 for the full
    gate) plus structural layer boundaries and adjacent frames.

    Requires a running Rails server.

    Usage:
      bin/rails 'animate_it:verify[<composition-id>]'
      bin/rails 'animate_it:verify[<composition-id>,1]'
      ANIMATE_IT_PROPS_JSON='{"title":"Variant"}' bin/rails 'animate_it:verify[<composition-id>,1]'
      ANIMATE_IT_PROPS_MATRIX_JSON='[{}, {"title":"Variant"}]' bin/rails 'animate_it:verify[<composition-id>,1]'

    Set ANIMATE_IT_READY_TIMEOUT_MS to override the 30000ms readiness timeout.
  DESC
  task :verify, %i[id step] => :environment do |_task, args|
    raise "Usage: bin/rails 'animate_it:verify[<composition-id>,(<step>)?]'" if args[:id].blank?

    AnimateIt.load_compositions!
    composition = AnimateIt.registry.fetch(args[:id])
    verify_composition!(
      composition,
      host: animate_it_render_host,
      step: (args[:step] || 10).to_i,
      props_variants: verification_props_variants(composition)
    )
  end

  desc <<~DESC
    Every-frame verification gate for every client-driven composition and each
    composition's declared `verification_props` variant.

    Requires a running Rails server.

    Usage:
      bin/rails animate_it:verify_all
      ANIMATE_IT_PROPS_MATRIX_JSON='[{}, {"title":"Variant"}]' bin/rails animate_it:verify_all
  DESC
  task verify_all: :environment do
    AnimateIt.load_compositions!
    compositions = AnimateIt.compositions.select(&:client_driven?)
    raise "No client-driven AnimateIt compositions are registered" if compositions.empty?

    compositions.each do |composition|
      verify_composition!(
        composition,
        host: animate_it_render_host,
        step: 1,
        props_variants: verification_props_variants(composition)
      )
    end

    puts "Verified #{compositions.size} client-driven compositions at every frame."
  end

  # Parse `30..120` / `30-120` / `30` (single frame) into a Range. Returns
  # nil for blank input, meaning "use the whole composition".
  def parse_frame_range(raw, composition)
    return nil if raw.blank?

    if raw.match?(/\A\d+\z/)
      n = raw.to_i
      return n..n
    end

    match = raw.match(/\A(\d+)\s*(?:\.\.|-)\s*(\d+)\z/)
    raise "Invalid frame range #{raw.inspect}. Use `start..end`, `start-end`, or a single frame number." unless match

    start_frame = match[1].to_i
    end_frame   = match[2].to_i
    raise "Frame range start (#{start_frame}) must be <= end (#{end_frame})." if start_frame > end_frame

    max = composition.duration_in_frames - 1
    end_frame = max if end_frame > max
    start_frame..end_frame
  end

  def progress_logger
    lambda do |frame, total|
      print "\r  frame #{frame} / #{total}"
      $stdout.flush
    end
  end

  def verification_props_variants(composition)
    matrix_json = ENV.fetch("ANIMATE_IT_PROPS_MATRIX_JSON", nil)
    single_json = ENV.fetch("ANIMATE_IT_PROPS_JSON", nil)
    return parse_props_matrix(matrix_json) if matrix_json.present?
    return [parse_props(single_json, "ANIMATE_IT_PROPS_JSON")] if single_json.present?

    composition.verification_props
  end

  def parse_props_matrix(raw)
    variants = JSON.parse(raw)
    valid_matrix = variants.is_a?(Array) && variants.present? && variants.all?(Hash)
    raise "ANIMATE_IT_PROPS_MATRIX_JSON must contain a non-empty JSON array of objects" unless valid_matrix

    variants.map(&:deep_symbolize_keys)
  rescue JSON::ParserError => e
    raise "ANIMATE_IT_PROPS_MATRIX_JSON must contain a JSON array of objects: #{e.message}"
  end

  def parse_props(raw, name)
    props = JSON.parse(raw)
    raise "#{name} must contain a JSON object" unless props.is_a?(Hash)

    props.deep_symbolize_keys
  rescue JSON::ParserError => e
    raise "#{name} must contain a JSON object: #{e.message}"
  end

  def verify_composition!(composition, host:, step:, props_variants:)
    props_variants.each_with_index do |props, variant_index|
      output_dir = Rails.root.join("tmp/animate_it/verify/#{composition.id}/variant-#{variant_index + 1}")
      verification = AnimateIt::Verification.new(
        composition:,
        host:,
        step:,
        props:,
        output_dir:,
        candidate_backend: ENV.fetch("ANIMATE_IT_VERIFY_BACKEND", "player").to_sym,
        ready_timeout: ENV.fetch("ANIMATE_IT_READY_TIMEOUT_MS", 30_000).to_i
      )
      puts "Verifying #{composition.id} variant #{variant_index + 1}/#{props_variants.size}: " \
           "#{verification.sample_frames.size} frames (step #{verification.step}, " \
           "RGB threshold #{verification.threshold}dB, alpha threshold #{verification.alpha_threshold}dB)"

      results = verification.call
      failures = results.reject(&:passed)
      print_verification_results(results)
      if failures.any?
        raise "#{failures.size}/#{results.size} frames below threshold. " \
              "Screenshots in #{verification.output_dir}"
      end

      puts "All #{results.size} frames match " \
           "(RGB >= #{verification.threshold}dB, alpha >= #{verification.alpha_threshold}dB)."
    end
  end

  def print_verification_results(results)
    results.each do |result|
      rgb = result.rgb_psnr.infinite? ? "identical" : format("%.2fdB", result.rgb_psnr)
      alpha = result.alpha_psnr.infinite? ? "identical" : format("%.2fdB", result.alpha_psnr)
      puts format(
        "  frame %<frame>5d  RGB %<rgb>s  alpha %<alpha>s%<flag>s",
        frame: result.frame,
        rgb:,
        alpha:,
        flag: result.passed ? "" : "  ← FAIL"
      )
    end
  end
end
