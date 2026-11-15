require "yaml"

# Optional <root>/.localito.yml:
#   paths: ["config/locales/**/*.yml"]   # globs, relative to root
#   locales: [es, en]                    # column order; the rest follow sorted
#   base: main                           # git ref to compare with (default HEAD)
class LocalitoConfig
  FILE = ".localito.yml"
  DEFAULT_PATHS = ["config/locales/**/*.yml"].freeze

  attr_reader :path, :paths, :locales, :base, :error

  def initialize(root)
    @path = File.join(root, FILE)
    @paths = DEFAULT_PATHS.dup
    @locales = []
    @base = "HEAD"
    @error = ""
    load_file if File.exist?(@path)
  end

  private

  def load_file
    data = YAML.safe_load(File.read(@path))
    return unless data.is_a?(Hash)

    paths = strings(data["paths"])
    @paths = paths unless paths.empty?
    @locales = strings(data["locales"])
    @base = data["base"].to_s unless data["base"].to_s.empty?
  rescue StandardError => e
    @error = "#{FILE}: #{e.message}"
  end

  def strings(node)
    return [] unless node.is_a?(Array)

    node.map(&:to_s)
  end
end
