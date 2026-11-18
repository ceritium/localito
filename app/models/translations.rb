require "digest"
require "fileutils"

# Every locale file under root, by key without its locale and then by locale.
# The first file to define a key wins, in glob order.
class Translations
  class Conflict < StandardError; end

  KEY_NAME = /\A[^\s.]+(\.[^\s.]+)*\z/

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

  # Changes whenever a file is added, removed or written, or HEAD moves; only
  # stats files and asks git for HEAD.
  def self.version(root)
    config = LocalitoConfig.new(root)
    paths = paths_for(root, config)
    signature = signature_for(root, config, paths, paths.map { |path| stamp(path) })
    Digest::SHA256.hexdigest("#{signature}|#{GitBase.head(root)}")[0, 16]
  end

  def self.paths_for(root, config)
    found = if config.discover?
              Discovery.paths(root)
            else
              config.paths.flat_map { |glob| Dir.glob(File.join(root, glob)) }.uniq.sort
            end
    return found if config.exclude.empty?

    patterns = config.exclude.map { |glob| GitBase.glob_regexp(glob) }
    found.reject { |path| patterns.any? { |re| re.match?(path.delete_prefix("#{root}/")) } }
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

  INTERPOLATION = /%\{(\w+)\}/

  attr_reader :root, :config, :files, :locales, :names, :base

  def initialize(root, config, files)
    @root = root
    @config = config
    @files = files
    @base = {}
    @base_key = ""
    @readonly_patterns = config.readonly.map { |glob| GitBase.glob_regexp(glob) }
    reindex
  end

  # The locale others are checked against: default_locale, else the first.
  def reference
    return @config.default_locale if @locales.include?(@config.default_locale)

    @locales.first.to_s
  end

  def readonly?(path)
    rel = relative(path)
    @readonly_patterns.any? { |re| re.match?(rel) }
  end

  # Whether the cell can be written: its entry's lines are known and its file
  # isn't read-only; a missing cell goes by the file it would be added to.
  def editable?(name, locale)
    entry = cell(name, locale)
    return entry.editable && !readonly?(entry.path) if entry

    !readonly?(target_path(name, locale))
  end

  # Every definition of name/locale when more than one file has it; the
  # first one is the value shown and edited.
  def duplicates(name, locale)
    row = @dups[name]
    list = row ? row[locale] : nil
    list || []
  end

  def duplicated?(name, locales = @locales)
    locales.any? { |locale| duplicates(name, locale).size > 1 }
  end

  def duplicate_count
    @dups.size
  end

  # "" or what differs from the reference locale's %{...} placeholders.
  def interpolation_issue(name, locale)
    ref = reference
    return "" if locale == ref

    mine = value(name, locale)
    theirs = value(name, ref)
    return "" if mine.nil? || theirs.nil? || mine.empty?

    have = mine.scan(INTERPOLATION).flatten.uniq
    want = theirs.scan(INTERPOLATION).flatten.uniq
    out = []
    (want - have).each { |v| out << "missing %{#{v}}" }
    (have - want).each { |v| out << "%{#{v}} isn't in #{ref}" }
    out.join(", ")
  end

  def interpolation_mismatch?(name, locales = @locales)
    locales.any? { |locale| !interpolation_issue(name, locale).empty? }
  end

  # Files grouped across locales: config/locales/devise.en.yml and
  # devise.es.yml are "config/locales/devise.*.yml".
  def group_of(file)
    rel = relative(file.path)
    found = file.entries.map(&:locale).uniq
    return rel unless found.size == 1

    locale = found.first
    dir = File.dirname(rel)
    base = File.basename(rel)
    base = base.sub(/\A#{Regexp.escape(locale)}(\.ya?ml|\.json)\z/) { "*#{Regexp.last_match(1)}" }
    base = base.sub(/\.#{Regexp.escape(locale)}(\.ya?ml|\.json)\z/) { ".*#{Regexp.last_match(1)}" }
    dir = "/#{dir}/".sub("/#{locale}/", "/*/")[1..-2] unless dir == "."
    dir == "." ? base : File.join(dir, base)
  end

  def groups
    @group_names.keys.sort
  end

  def group_names(group)
    @group_names[group] || []
  end

  # A group ("x/devise.*.yml") or a folder ending in "/" ("x/").
  def in_scope?(name, scope)
    return true if scope.empty?
    return group_names(scope).include?(name) unless scope.end_with?("/")

    @group_names.any? { |group, names| group.start_with?(scope) && names.include?(name) }
  end

  # Folders and groups, depth-first, with key and missing counts over locales.
  def tree(locales)
    rows = []
    seen = {}
    groups.each do |group|
      parts = group.split("/")
      parts[0..-2].each_with_index do |_, i|
        folder = "#{parts[0..i].join('/')}/"
        next if seen[folder]

        seen[folder] = true
        names = @group_names.select { |g, _| g.start_with?(folder) }.values.flatten.uniq
        rows << TreeRow.new(folder, "#{parts[i]}/", i, true, names.size, missing_in(names, locales))
      end
      names = group_names(group)
      rows << TreeRow.new(group, parts.last, parts.size - 1, false, names.size, missing_in(names, locales))
    end
    rows
  end

  # Compares against these values ("es.posts.title" => value) from now on;
  # keys only the base has are listed too, as removed.
  def compare(base_key, values)
    return if base_key == @base_key

    @base_key = base_key
    @base = values
    reindex
  end

  def cell(name, locale)
    row = @cells[name]
    row ? row[locale] : nil
  end

  def value(name, locale)
    entry = cell(name, locale)
    entry ? entry.value : nil
  end

  def base_value(name, locale)
    @base["#{locale}.#{name}"]
  end

  # "added", "removed", "modified" or "" against the base.
  def change(name, locale)
    return "" if @base_key.empty?

    now = value(name, locale)
    before = base_value(name, locale)
    return "" if now == before
    return "added" if before.nil?
    return "removed" if now.nil?

    "modified"
  end

  def changed?(name, locales = @locales)
    locales.any? { |locale| !change(name, locale).empty? }
  end

  def missing?(name, locales = @locales)
    locales.any? { |locale| cell(name, locale).nil? }
  end

  def empty?(name, locales = @locales)
    locales.any? { |locale| value(name, locale) == "" }
  end

  def comparing?
    !@base_key.empty?
  end

  # filter: "" | "missing" | "missing:<locale>" | "empty" | "changed" |
  # "duplicated" | "interpolation"; scope: see in_scope?
  def search(query, filter, locales, scope = "")
    q = query.downcase
    only = filter.start_with?("missing:") ? [filter.delete_prefix("missing:")] : locales
    @names.select do |name|
      next false unless in_scope?(name, scope)
      next false if filter == "duplicated" && !duplicated?(name, locales)
      next false if filter == "interpolation" && !interpolation_mismatch?(name, locales)
      next false if filter == "missing" && !missing?(name, only)
      next false if filter.start_with?("missing:") && !missing?(name, only)
      next false if filter == "empty" && !empty?(name, locales)
      next false if filter == "changed" && !changed?(name, locales)
      next true if q.empty? || name.downcase.include?(q)

      locales.any? do |locale|
        v = value(name, locale)
        v && v.downcase.include?(q)
      end
    end
  end

  # locale => [translated, missing, changed], over the keys in the files now.
  def stats
    out = {}
    @locales.each do |locale|
      present = 0
      changed = 0
      @current_names.each { |name| present += 1 if cell(name, locale) }
      @names.each { |name| changed += 1 unless change(name, locale).empty? }
      out[locale] = [present, @current_names.size - present, changed]
    end
    out
  end

  def key_count
    @current_names.size
  end

  def changes
    out = []
    @names.each do |name|
      @locales.each do |locale|
        kind = change(name, locale)
        out << [name, locale, kind] unless kind.empty?
      end
    end
    out
  end

  # Writes value at name/locale. original is what the form showed: the edit
  # is refused if the file no longer holds it (or now holds a missing key).
  def set(name, locale, value, original, was_missing)
    entry = cell(name, locale)
    if was_missing
      raise Conflict, "#{locale}.#{name} was added on disk meanwhile" if entry

      add(name, locale, value)
    else
      raise Conflict, "#{locale}.#{name} was removed on disk meanwhile" unless entry
      raise Conflict, "#{locale}.#{name} changed on disk meanwhile" if entry.value != original
      raise ArgumentError, "#{locale}.#{name} can't be edited here" unless entry.editable
      raise ArgumentError, "#{relative(entry.path)} is read-only" if readonly?(entry.path)

      file(entry.path).update(entry.key, value)
      reindex
    end
  end

  def add(name, locale, value)
    raise ArgumentError, "Invalid key: #{name}" unless name.match?(KEY_NAME)
    raise ArgumentError, "Invalid locale: #{locale}" unless locale.match?(/\A[\w-]+\z/)

    path = target_path(name, locale)
    raise ArgumentError, "#{relative(path)} is read-only" if readonly?(path)

    target = file(path)
    unless target
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "") unless File.exist?(path)
      target = LocaleFile.new(path)
      @files << target
    end
    target.insert("#{locale}.#{name}", value)
    reindex
  end

  # Where a new locale/name goes: the existing counterpart of a file that has
  # the key in another locale (devise.en.yml -> devise.es.yml), else the file
  # of that locale sharing the longest key prefix, else that counterpart
  # created, else new_keys (config/locales/<locale>.yml).
  def target_path(name, locale)
    fallback = ""
    @locales.each do |other|
      entry = cell(name, other)
      next unless entry

      mirrored = mirror_path(entry.path, other, locale)
      next if mirrored.empty?
      return mirrored if file(mirrored)

      fallback = mirrored if fallback.empty?
    end

    best = ""
    best_score = 0
    parts = name.split(".")
    @files.each do |f|
      next if readonly?(f.path)

      f.entries.each do |e|
        next unless e.locale == locale

        other = e.name.split(".")
        score = 0
        score += 1 while score < parts.size && score < other.size && parts[score] == other[score]
        if score > best_score
          best_score = score
          best = f.path
        end
      end
    end
    return best unless best.empty?
    return fallback unless fallback.empty?

    File.join(@root, @config.new_keys.gsub("%{locale}", locale))
  end

  # What applying these [name, locale, value] rows would do to each cell.
  def preview_import(rows)
    rows.map do |name, locale, value|
      value = value.gsub("\r\n", "\n")
      entry = cell(name, locale)
      current = entry ? entry.value : ""
      if !name.match?(KEY_NAME)
        ImportRow.new(name, locale, value, current, "error", "invalid key")
      elsif !locale.match?(/\A[\w-]+\z/)
        ImportRow.new(name, locale, value, current, "error", "invalid locale")
      elsif entry && entry.value == value
        ImportRow.new(name, locale, value, current, "same", "")
      elsif !editable?(name, locale)
        ImportRow.new(name, locale, value, current, "error", "can't be written here")
      elsif entry
        ImportRow.new(name, locale, value, current, "changed", "")
      else
        ImportRow.new(name, locale, value, current, "new", "would go to #{relative(target_path(name, locale))}")
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

  private

  def missing_in(names, locales)
    count = 0
    names.each { |name| locales.each { |locale| count += 1 unless cell(name, locale) } }
    count
  end

  def reindex
    @cells = {}
    @dups = {}
    @group_names = {}
    @files.each do |file|
      group = group_of(file)
      names = @group_names[group] || []
      file.entries.each do |entry|
        names << entry.name
        row = @cells[entry.name] || {}
        if row.key?(entry.locale)
          dups = @dups[entry.name] || {}
          dups[entry.locale] = [row[entry.locale]] unless dups.key?(entry.locale)
          dups[entry.locale] << entry
          @dups[entry.name] = dups
        else
          row[entry.locale] = entry
        end
        @cells[entry.name] = row
      end
      @group_names[group] = names.uniq
    end
    found = @cells.values.flat_map(&:keys).uniq
    @base.each_key { |key| found << key.split(".").first.to_s }
    found = found.uniq.reject(&:empty?)
    order = ([@config.default_locale] + @config.locales).reject(&:empty?).uniq
    @locales = order.select { |l| found.include?(l) } + (found - order).sort
    @current_names = @cells.keys.sort
    names = @current_names.dup
    @base.each_key do |key|
      name = key.split(".").drop(1).join(".")
      names << name unless name.empty? || @cells.key?(name)
    end
    @names = names.uniq.sort
  end

  def mirror_path(path, from, to)
    rel = relative(path)
    dir = File.dirname(rel)
    base = File.basename(rel)
    candidates = []
    %w[.yml .yaml .json].each do |ext|
      candidates << File.join(dir, "#{to}#{ext}") if base == "#{from}#{ext}"
      candidates << File.join(dir, base.delete_suffix(".#{from}#{ext}") + ".#{to}#{ext}") if base.end_with?(".#{from}#{ext}")
    end
    candidates << rel.sub("/#{from}/", "/#{to}/") if rel.include?("/#{from}/")
    candidates.each do |c|
      return File.join(@root, c) unless c == rel
    end
    ""
  end
end
