# Every locale file under root, by key without its locale and then by locale.
# The first file to define a key wins, as Dir.glob order is what we show.
class Translations
  attr_reader :root, :files, :locales, :names

  def initialize(root)
    @root = root
    @files = Dir.glob("#{root}/config/locales/**/*.yml").sort.map { |path| LocaleFile.new(path) }
    @cells = {}
    @files.each do |file|
      file.entries.each do |entry|
        row = @cells[entry.name] || {}
        row[entry.locale] = entry unless row.key?(entry.locale)
        @cells[entry.name] = row
      end
    end
    @locales = @cells.values.flat_map(&:keys).uniq.sort
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

  def broken_files
    @files.reject { |f| f.error.empty? }
  end

  def relative(path)
    path.delete_prefix("#{@root}/")
  end
end
