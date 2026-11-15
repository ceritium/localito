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

  # Leaves keyed "es.posts.index.title"; an Array is shown joined and read-only.
  def self.flatten(node, prefix, out, complex)
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

  def self.values(content)
    out = {}
    flatten(YAML.safe_load(content, aliases: true), "", out, {})
    out
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
    write_checked(content, key, value)
  end

  # Adds a key that isn't there, under its deepest existing parent, indented
  # like that parent's children; missing parents are created on the way.
  def insert(key, value)
    raise ArgumentError, @error unless @error.empty?
    raise ArgumentError, "#{key} already exists in #{@path}" if entry(key)

    lines = File.read(@path).split("\n", -1)
    positions = scan(lines)
    parts = key.split(".")
    depth = parts.size - 1
    depth -= 1 while depth.positive? && !positions.key?(parts[0, depth].join("."))

    if depth.positive?
      parent = parts[0, depth].join(".")
      raise ArgumentError, "#{parent} has a value; #{key} can't go under it" if entry(parent)

      at = subtree_end(positions, parent)
      indent = child_indent(positions, parent)
      step = indent - positions[parent][3]
    else
      at = lines.rindex { |l| !l.strip.empty? }.to_i + (lines.any? { |l| !l.strip.empty? } ? 1 : 0)
      indent = 0
      step = 2
    end

    added = []
    parts[depth..-2].each_with_index do |part, i|
      added << "#{' ' * (indent + (i * step))}#{yaml_key(part)}:"
    end
    leaf_indent = indent + ((parts.size - 1 - depth) * step)
    added += scalar_lines("#{' ' * leaf_indent}#{yaml_key(parts.last)}:", leaf_indent, value, "plain")
    content = (lines[0, at] + added + lines[at..]).join("\n")
    content += "\n" unless content.end_with?("\n")
    write_checked(content, key, value)
  end

  private

  def write_checked(content, key, value)
    expected = {}
    @entries.each { |e| expected[e.key] = e.value }
    expected[key] = value
    actual = {}
    begin
      LocaleFile.flatten(YAML.safe_load(content, aliases: true), "", actual, {})
    rescue StandardError => e
      raise ArgumentError, "Writing #{key} would break #{@path}: #{e.message}"
    end
    raise ArgumentError, "Writing #{key} would change other values in #{@path}" unless actual == expected

    File.write(@path, content)
    load_entries(content)
  end

  def subtree_end(positions, key)
    last = 0
    positions.each do |k, pos|
      last = pos[1] if (k == key || k.start_with?("#{key}.")) && pos[1] > last
    end
    last
  end

  def child_indent(positions, key)
    depth = key.count(".") + 1
    positions.each do |k, pos|
      return pos[3] if k.start_with?("#{key}.") && k.count(".") == depth
    end
    positions[key][3] + 2
  end

  # Plain when YAML reads it back as that same String key; "no" or "on" aren't.
  def yaml_key(part)
    if part.match?(/\A[A-Za-z_][\w-]*\z/)
      loaded = YAML.safe_load("#{part}: x")
      return part if loaded.is_a?(Hash) && loaded.keys.first == part
    end
    double_quote(part)
  rescue StandardError
    double_quote(part)
  end

  def load_entries(content)
    @entries = []
    @error = ""
    values = {}
    complex = {}
    begin
      LocaleFile.flatten(YAML.safe_load(content, aliases: true), "", values, complex)
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

  # key => [first line, last line, style, indent], lines 1-based. A leaf owns every deeper
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
        # A value on the line after its key ("key:\n  'text'") belongs to it.
        positions[bare_key][1] = i + 1 unless bare_key.empty?
        next
      end

      stack.pop while !stack.empty? && stack.last[0] >= indent
      stack << [indent, unquote(m[2])]
      full = stack.map { |s| s[1] }.join(".")
      rest = m[3].to_s.sub(/\A&\S+/, "").strip
      if rest.empty? || rest.start_with?("#")
        positions[full] = [i + 1, i + 1, "plain", indent]
        bare_key = full
      else
        positions[full] = [i + 1, i + 1, style_of(rest), indent]
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
