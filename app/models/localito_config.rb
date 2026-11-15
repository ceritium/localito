require "yaml"

# Optional <root>/.localito.yml:
#   paths: ["config/locales/**/*.yml"]   # globs, relative to root
#   locales: [es, en]                    # column order; the rest follow sorted
class LocalitoConfig
  FILE = ".localito.yml"
  DEFAULT_PATHS = ["config/locales/**/*.yml"].freeze

  attr_reader :path, :paths, :locales, :error

  def initialize(root)
    @path = File.join(root, FILE)
    @paths = DEFAULT_PATHS.dup
    @locales = []
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
  rescue StandardError => e
    @error = "#{FILE}: #{e.message}"
  end

  def strings(node)
    return [] unless node.is_a?(Array)

    node.map(&:to_s)
  end
end
