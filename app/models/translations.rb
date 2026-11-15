require "digest"

# Every locale file under root, by key without its locale and then by locale.
# The first file to define a key wins, in glob order.
class Translations
  @files = {}
  @latest = nil
  @latest_stamp = ""

  # Parsed files are kept per process and reused while their mtime and size
  # hold, so only files changed since the last request are read again.
  def self.load(root)
    config = LocalitoConfig.new(root)
    paths = paths_for(root, config)
    stamps = paths.map { |path| stamp(path) }
    signature = signature_for(root, config, paths, stamps)
    latest = @latest
    return latest if latest && @latest_stamp == signature

    files = paths.each_with_index.map do |path, i|
      cached = @files[path]
      if cached && cached[0] == stamps[i]
        cached[1]
      else
        file = LocaleFile.new(path)
        @files[path] = [stamps[i], file]
        file
      end
    end
    @latest = new(root, config, files)
    @latest_stamp = signature
    @latest
  end

  # Changes whenever a file is added, removed or written; only stats files.
  def self.version(root)
    config = LocalitoConfig.new(root)
    paths = paths_for(root, config)
    Digest::SHA256.hexdigest(signature_for(root, config, paths, paths.map { |path| stamp(path) }))[0, 16]
  end

  def self.paths_for(root, config)
    config.paths.flat_map { |glob| Dir.glob(File.join(root, glob)) }.uniq.sort
  end

  def self.signature_for(root, config, paths, stamps)
    parts = [root, stamp(config.path)]
    paths.each_with_index { |path, i| parts << "#{path}:#{stamps[i]}" }
    parts.join("|")
  end

  def self.stamp(path)
    return "" unless File.exist?(path)

    "#{File.mtime(path).to_f}:#{File.size(path)}"
  end

  attr_reader :root, :config, :files, :locales, :names

  def initialize(root, config, files)
    @root = root
    @config = config
    @files = files
    @cells = {}
    @files.each do |file|
      file.entries.each do |entry|
        row = @cells[entry.name] || {}
        row[entry.locale] = entry unless row.key?(entry.locale)
        @cells[entry.name] = row
      end
    end
    found = @cells.values.flat_map(&:keys).uniq
    @locales = config.locales.select { |l| found.include?(l) } + (found - config.locales).sort
    @names = @cells.keys.sort
  end

  def cell(name, locale)
    row = @cells[name]
    row ? row[locale] : nil
  end

  def missing?(name)
    @locales.any? { |locale| cell(name, locale).nil? }
  end

  def search(query, missing_only)
    q = query.downcase
    @names.select do |name|
      next false if missing_only && !missing?(name)
      next true if q.empty? || name.downcase.include?(q)

      @locales.any? do |locale|
        entry = cell(name, locale)
        entry && entry.value.downcase.include?(q)
      end
    end
  end

  def file(path)
    @files.find { |f| f.path == path }
  end

  def errors
    out = []
    out << @config.error unless @config.error.empty?
    @files.each { |f| out << "#{relative(f.path)}: #{f.error}" unless f.error.empty? }
    out
  end

  def relative(path)
    path.delete_prefix("#{@root}/")
  end
end
