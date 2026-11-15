require "yaml"

# Values come from YAML itself; the line scan only locates each key so an edit
# can replace its lines and keep the rest of the file (comments, order) intact.
class LocaleFile
  KEY_LINE = /\A( *)("(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[^\s#'"\-][^:#]*?|-[^\s:#][^:#]*?) *:(?: +(.*))?\z/

  ESCAPES = { "\\" => "\\\\", '"' => '\\"', "\n" => "\\n", "\t" => "\\t" }.freeze

  attr_reader :path, :entries, :error

  def initialize(path)
    @path = path
    @entries = []
    @error = ""
    load_entries(File.read(path))
  end

  def entry(key)
    @entries.find { |e| e.key == key }
  end

  # Raises if the rewritten file wouldn't load back with the new value and every
  # other value untouched; the file is only written after that check.
  def update(key, value)
    target = entry(key)
    raise ArgumentError, "#{key} not found in #{@path}" unless target
    raise ArgumentError, "#{key} can't be edited here" unless target.editable

    lines = File.read(@path).split("\n", -1)
    head = lines[target.line - 1].match(KEY_LINE)
    replacement = scalar_lines("#{head[1]}#{head[2]}:", head[1].length, value, target.style)
    content = (lines[0, target.line - 1] + replacement + lines[target.last_line..]).join("\n")

    expected = {}
    @entries.each { |e| expected[e.key] = e.value }
    expected[key] = value
    actual = {}
    flatten(YAML.safe_load(content, aliases: true), "", actual, {})
    raise ArgumentError, "Writing #{key} would change other values in #{@path}" unless actual == expected

    File.write(@path, content)
    load_entries(content)
  end

  private

  def load_entries(content)
    @entries = []
    values = {}
    complex = {}
    begin
      flatten(YAML.safe_load(content, aliases: true), "", values, complex)
    rescue StandardError => e
      @error = e.message
      return
    end
    positions = scan(content.split("\n", -1))
    values.each do |key, value|
      pos = positions[key]
      editable = !pos.nil? && !complex.key?(key)
      @entries << LocaleEntry.new(@path, key, value, pos ? pos[0] : 0, pos ? pos[1] : 0,
                                  pos ? pos[2] : "", editable)
    end
  end

  # Leaves keyed "es.posts.index.title"; an Array is shown joined and read-only.
  def flatten(node, prefix, out, complex)
    if node.is_a?(Hash)
      node.each do |k, v|
        flatten(v, prefix.empty? ? k.to_s : "#{prefix}.#{k}", out, complex)
      end
    elsif node.is_a?(Array)
      out[prefix] = node.map(&:to_s).join(", ")
      complex[prefix] = true
    elsif !prefix.empty?
      out[prefix] = node.to_s
    end
  end

  # key => [first line, last line, style], 1-based. A leaf owns every deeper
  # line after it (block scalars, wrapped quotes); "- " lines belong to the
  # last key that had no inline value.
  def scan(lines)
    positions = {}
    stack = []
    open_key = ""
    open_indent = -1
    bare_key = ""
    lines.each_with_index do |line, i|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?("#") || stripped == "---"

      indent = line.length - line.lstrip.length
      if !open_key.empty? && indent > open_indent
        positions[open_key][1] = i + 1
        next
      end
      open_key = ""
      if stripped.start_with?("- ") || stripped == "-"
        positions[bare_key][1] = i + 1 unless bare_key.empty?
        next
      end
      m = line.match(KEY_LINE)
      unless m
        bare_key = ""
        next
      end

      stack.pop while !stack.empty? && stack.last[0] >= indent
      stack << [indent, unquote(m[2])]
      full = stack.map { |s| s[1] }.join(".")
      rest = m[3].to_s.sub(/\A&\S+/, "").strip
      if rest.empty? || rest.start_with?("#")
        positions[full] = [i + 1, i + 1, "plain"]
        bare_key = full
      else
        positions[full] = [i + 1, i + 1, style_of(rest)]
        open_key = full
        open_indent = indent
        bare_key = ""
      end
    end
    positions
  end

  def style_of(rest)
    return "double" if rest.start_with?('"')
    return "single" if rest.start_with?("'")
    return "block" if rest.start_with?("|", ">")

    "plain"
  end

  def unquote(key)
    return key[1..-2].gsub(/\\(.)/) { Regexp.last_match(1) } if key.start_with?('"')
    return key[1..-2].gsub("''", "'") if key.start_with?("'")

    key
  end

  # Keeps the entry's quoting style when the value allows it.
  def scalar_lines(head, indent, value, style)
    if value.include?("\n")
      return block_lines(head, indent, value) if block_safe?(value)

      return ["#{head} #{double_quote(value)}"]
    end
    return ["#{head} '#{value.gsub("'", "''")}'"] if style == "single"
    return ["#{head} #{value}"] if style != "double" && plain_safe?(value)

    ["#{head} #{double_quote(value)}"]
  end

  def block_lines(head, indent, value)
    pad = " " * (indent + 2)
    body = value.end_with?("\n") ? value[0..-2] : value
    out = ["#{head} #{value.end_with?("\n") ? '|' : '|-'}"]
    body.split("\n", -1).each { |l| out << (l.empty? ? "" : "#{pad}#{l}") }
    out
  end

  def block_safe?(value)
    return false if value.end_with?("\n\n") || value.start_with?(" ")

    value.split("\n").none? { |l| l.start_with?(" ", "\t") }
  end

  # Plain only when YAML reads it back as the same String (not true, 1, nil...).
  def plain_safe?(value)
    return false if value.empty? || value != value.strip
    return false if value.include?(": ") || value.include?(" #") || value.end_with?(":")
    return false if "-?:,[]{}#&*!|>'\"%@`".include?(value[0])

    YAML.safe_load(value) == value
  rescue StandardError
    false
  end

  def double_quote(value)
    escaped = value.gsub(/[\\"\n\t]/) { |c| ESCAPES[c] }
    "\"#{escaped}\""
  end
end
