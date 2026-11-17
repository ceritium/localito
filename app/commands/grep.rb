# localito grep: search this app's locale files by key or value from the
# terminal, with the file and line of every match. Spinrail compiles this
# file into the binary and runs it when the first argument is "grep" (see
# Spinrail::Build#commands_source), so it reads the same files the browser
# does: LocalitoConfig paths and exclude, or Discovery when there are none.
class Grep
  USAGE = [
    "Usage: localito grep [options]",
    "",
    "Searches the locale files the browser shows and prints every matching",
    "entry with its file, line and key. Without -k or -v every entry is listed.",
    "",
    "Options:",
    "  -k, --key TEXT        only keys that contain TEXT",
    "  -v, --value TEXT      only values that contain TEXT",
    "  -l, --locale CODES    only these locales, comma-separated (en,es)",
    "  -s, --case-sensitive  don't ignore case",
    "      --changed         only entries that changed since --base",
    "      --base REF        git ref to compare with (default: from the config, HEAD)",
    "      --no-color        plain output, no escape codes",
    "  -c, --config PATH     config file (default: DIR/.localito.yml)",
    "  -h, --help            this help",
    "",
    "Exit code 1 when nothing matched."
  ].join("\n")

  # Values with line breaks (block strings) are flattened and cut.
  MAX_VALUE = 60

  # Options that take a value.
  VALUE_FLAGS = ["-k", "--key", "-v", "--value", "-l", "--locale", "--base", "-c", "--config"].freeze

  BLUE = "\e[94m".freeze
  YELLOW = "\e[33m".freeze
  RED = "\e[91m".freeze
  GRAY = "\e[90m".freeze
  RESET = "\e[0m".freeze

  def self.run(argv)
    Grep.new(argv).run
  end

  def initialize(argv)
    @argv = argv
    @key = ""
    @value = ""
    @locales = []
    @sensitive = false
    @changed = false
    @base = ""
    @help = false
    @error = ""
    @color = $stdout.tty? && ENV.fetch("NO_COLOR", "").empty? && ENV.fetch("TERM", "") != "dumb"
  end

  def run
    parse
    unless @error.empty?
      warn "localito grep: #{@error}"
      warn USAGE
      return 2
    end
    if @help
      puts USAGE
      return 0
    end

    root = File.expand_path(ENV.fetch("LOCALITO_ROOT", "."))
    config = LocalitoConfig.new(root)
    translations = Translations.load(root)
    if @changed
      ref = @base.empty? ? config.base : @base
      base = GitBase.new(root, ref, config.paths, config.exclude)
      unless base.available?
        warn "localito grep: #{base.error}"
        return 2
      end
      translations.compare(base.sha, base.values)
    end

    matched = 0
    translations.files.sort_by(&:path).each do |file|
      rows = file.entries.select { |entry| matches?(entry, translations) }
      next if rows.empty?

      matched += rows.size
      puts colorize(translations.relative(file.path), BLUE)
      rows.each { |entry| puts line_for(entry, translations) }
      puts ""
    end
    matched.positive? ? 0 : 1
  end

  private

  def parse
    args = @argv
    i = args[0].to_s == "grep" ? 1 : 0
    while i < args.length
      arg = args[i].to_s
      if arg == "-h" || arg == "--help"
        @help = true
      elsif arg == "-s" || arg == "--case-sensitive"
        @sensitive = true
      elsif arg == "--changed"
        @changed = true
      elsif arg == "--no-color"
        @color = false
      elsif VALUE_FLAGS.include?(arg)
        i += 1
        if i >= args.length
          @error = "#{arg} needs a value"
          return
        end
        assign(arg, args[i].to_s)
      elsif arg.start_with?("--key=")
        @key = arg.delete_prefix("--key=")
      elsif arg.start_with?("--value=")
        @value = arg.delete_prefix("--value=")
      elsif arg.start_with?("--locale=")
        assign("-l", arg.delete_prefix("--locale="))
      elsif arg.start_with?("--base=")
        @base = arg.delete_prefix("--base=")
      elsif arg.start_with?("--config=")
        assign("-c", arg.delete_prefix("--config="))
      elsif arg.start_with?("-")
        @error = "unknown option #{arg}"
        return
      else
        @error = "unexpected argument #{arg}"
        return
      end
      i += 1
    end
  end

  def assign(flag, value)
    if flag == "-k" || flag == "--key"
      @key = value
    elsif flag == "-v" || flag == "--value"
      @value = value
    elsif flag == "-l" || flag == "--locale"
      @locales = value.split(",").map(&:strip).reject(&:empty?)
    elsif flag == "--base"
      @base = value
    else
      # LocalitoConfig reads it, and the cache key includes the config file.
      ENV["LOCALITO_CONFIG"] = File.expand_path(value)
    end
  end

  def matches?(entry, translations)
    return false unless @locales.empty? || @locales.include?(entry.locale)
    return false if @changed && translations.change(entry.name, entry.locale).empty?

    contains?(entry.key, @key) && contains?(entry.value.to_s, @value)
  end

  def contains?(text, needle)
    return true if needle.empty?
    return text.include?(needle) if @sensitive

    text.downcase.include?(needle.downcase)
  end

  def line_for(entry, translations)
    kind = @changed ? translations.change(entry.name, entry.locale) : ""
    note = kind.empty? ? "" : colorize(" (#{kind})", GRAY)
    number = colorize("#{entry.line.to_s.rjust(4)}:", YELLOW)
    arrow = colorize(" => ", GRAY)
    "#{number} #{highlight(entry.key, @key)}#{arrow}#{highlight(shortened(entry.value.to_s), @value)}#{note}"
  end

  def shortened(value)
    plain = value.gsub(/\s+/, " ").strip
    plain.length > MAX_VALUE ? "#{plain[0, MAX_VALUE - 3]}..." : plain
  end

  def highlight(text, needle)
    return text if !@color || needle.empty?

    hay = @sensitive ? text : text.downcase
    pick = @sensitive ? needle : needle.downcase
    out = +""
    pos = 0
    at = hay.index(pick)
    while at
      out << text[pos, at - pos] << RED << text[at, pick.length] << RESET
      pos = at + pick.length
      at = hay.index(pick, pos)
    end
    out << text[pos, text.length - pos]
  end

  def colorize(text, color)
    @color ? color + text + RESET : text
  end
end
