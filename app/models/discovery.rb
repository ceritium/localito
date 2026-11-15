# Without `paths` in the config: every YAML file whose first top-level key is
# a locale (en:, pt-BR:), so database.yml or CI workflows stay out.
class Discovery
  SKIP = %w[node_modules vendor tmp log public coverage storage].freeze
  EXTENSIONS = [".yml", ".yaml"].freeze
  LOCALE_ROOT = /\A["']?[a-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*["']?:\s*(?:&\w+\s*)?(?:#.*)?\z/
  MAX_DEPTH = 12

  @checked = {}

  def self.paths(root)
    found = []
    walk(root, found, 0)
    found.select { |path| locale_file?(path) }.sort
  end

  # Repo-relative paths from git, before their content is checked.
  def self.candidate?(path)
    parts = path.split("/")
    EXTENSIONS.include?(File.extname(path)) && parts[0..-2].none? { |dir| skip?(dir) }
  end

  def self.locale_root?(content)
    LocaleFile.lines_of(content).each do |line|
      text = line.strip
      next if text.empty? || text.start_with?("#") || text == "---"

      return LOCALE_ROOT.match?(line.rstrip)
    end
    false
  end

  def self.skip?(dir)
    dir.start_with?(".") || SKIP.include?(dir)
  end

  # Stats every candidate on each poll but reads only those that changed.
  def self.locale_file?(path)
    stamp = Translations.stamp(path)
    cached = @checked[path]
    return cached[1] if cached && cached[0] == stamp

    ok = locale_root?(File.read(path))
    @checked[path] = [stamp, ok]
    ok
  end

  def self.walk(dir, found, depth)
    return if depth > MAX_DEPTH

    Dir.children(dir).sort.each do |name|
      path = File.join(dir, name)
      if File.directory?(path)
        walk(path, found, depth + 1) unless skip?(name)
      elsif EXTENSIONS.include?(File.extname(name))
        found << path
      end
    end
  end
end
