require "digest"
require "pathname"
require "yaml"

module AnimateIt
  # Validates source inputs that a host application needs to reproduce its
  # compositions. Media remains owned by the host; the gem only defines the
  # manifest contract and checksum/provenance preflight.
  class AssetManifest
    Result = Data.define(:checked, :errors) do
      def success?
        errors.empty?
      end
    end

    attr_reader :root, :path

    def initialize(root: Rails.root, path: nil)
      @root = Pathname(root).expand_path
      @path = Pathname(path || @root.join("config/animate_it_assets.yml"))
    end

    def validate
      manifest = load_manifest
      assets = manifest.fetch("assets")
      errors = []
      errors << "manifest version must be 1" unless manifest["version"] == 1
      errors.concat(validate_assets(assets))
      Result.new(assets.size, errors)
    rescue Errno::ENOENT
      Result.new(0, ["asset manifest not found: #{path}"])
    rescue KeyError, Psych::Exception => e
      Result.new(0, ["invalid asset manifest #{path}: #{e.message}"])
    end

    def validate!
      result = validate
      return result if result.success?

      raise Error, "AnimateIt asset preflight failed:\n- #{result.errors.join("\n- ")}"
    end

    private

    def load_manifest
      YAML.safe_load_file(path, aliases: false).tap do |manifest|
        raise KeyError, "top level must be a mapping" unless manifest.is_a?(Hash)
        raise KeyError, "assets must be an array" unless manifest["assets"].is_a?(Array)
      end
    end

    def validate_assets(assets)
      errors = []
      paths = assets.filter_map do |asset|
        asset["path"] if asset.is_a?(Hash) && !asset["path"].to_s.empty?
      end
      paths.tally.each { |asset_path, count| errors << "duplicate asset path: #{asset_path}" if count > 1 }
      assets.each_with_index { |asset, index| errors.concat(validate_asset(asset, index)) }
      errors
    end

    def validate_asset(asset, index)
      return ["asset ##{index + 1} must be a mapping"] unless asset.is_a?(Hash)

      relative_path = asset["path"].to_s
      label = relative_path.empty? ? "asset ##{index + 1}" : relative_path
      provenance = asset["provenance"]
      errors = []
      errors << "#{label}: path is required" if relative_path.empty?
      errors << "#{label}: sha256 must be 64 lowercase hex characters" \
        unless asset["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
      errors << "#{label}: provenance.provider is required" \
        unless provenance.is_a?(Hash) && !provenance["provider"].to_s.empty?
      return errors if relative_path.empty?

      absolute_path = root.join(relative_path).cleanpath
      unless absolute_path.to_s.start_with?("#{root}#{File::SEPARATOR}")
        errors << "#{label}: path must remain inside #{root}"
        return errors
      end
      unless absolute_path.file?
        errors << "#{label}: file is missing"
        return errors
      end

      actual_sha = Digest::SHA256.file(absolute_path).hexdigest
      errors << "#{label}: checksum mismatch (expected #{asset["sha256"]}, got #{actual_sha})" \
        if actual_sha != asset["sha256"]
      errors
    end
  end
end
