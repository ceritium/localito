require "yaml"

# <root>/.localito.yml, or the file in LOCALITO_CONFIG (localito -c PATH).
# Every setting is optional; `localito init` writes them all with defaults.
class LocalitoConfig
  FILE = ".localito.yml"
  DEFAULT_PATHS = ["config/locales/**/*.yml"].freeze
  DEFAULT_NEW_KEYS = "config/locales/%{locale}.yml".freeze

  attr_reader :path, :paths, :exclude, :readonly, :locales, :default_locale, :base, :new_keys, :error

  def initialize(root)
    given = ENV["LOCALITO_CONFIG"].to_s
    @path = given.empty? ? File.join(root, FILE) : File.expand_path(given)
    @paths = DEFAULT_PATHS.dup
    @exclude = []
    @readonly = []
    @locales = []
    @default_locale = ""
    @base = "HEAD"
    @new_keys = DEFAULT_NEW_KEYS
    @error = ""
    if File.exist?(@path)
      load_file
    elsif !given.empty?
      @error = "#{@path}: no such file"
    end
  end

  def file?
    File.exist?(@path)
  end

  private

  def load_file
    data = YAML.safe_load(File.read(@path))
    return unless data.is_a?(Hash)

    paths = strings(data["paths"])
    @paths = paths unless paths.empty?
    @exclude = strings(data["exclude"])
    @readonly = strings(data["readonly"])
    @locales = strings(data["locales"])
    @default_locale = data["default_locale"].to_s
    @base = data["base"].to_s unless data["base"].to_s.empty?
    new_keys = data["new_keys"].to_s
    unless new_keys.empty?
      if new_keys.include?("%{locale}")
        @new_keys = new_keys
      else
        @error = "#{File.basename(@path)}: new_keys needs %{locale} in it"
      end
    end
  rescue StandardError => e
    @error = "#{File.basename(@path)}: #{e.message}"
  end

  def strings(node)
    return [] unless node.is_a?(Array)

    node.map(&:to_s)
  end
end
