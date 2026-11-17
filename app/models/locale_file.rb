require "yaml"

# Values come from YAML itself; the line scan only locates each key so an edit
# can replace its lines and keep the rest of the file (comments, order) intact.
class LocaleFile
  KEY_LINE = /\A( *)("(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[^\s#'"\-][^:#]*?|-[^\s:#][^:#]*?) *:(?: +(.*))?\z/

  ESCAPES = { "\\" => "\\\\", '"' => '\\"', "\n" => "\\n", "\t" => "\\t" }.freeze
  DATE_VALUE = /\A(\s*(?:- +|.*?: +))(\d{4}-\d\d?-\d\d?(?:[Tt ][\d:.]+(?: *(?:Z|[-+]\d\d?(?::?\d\d)?))?)?) *(#.*)?\z/
  RUBY_TAG = %r{\A(\s*(?:- +|.*?: +))!ruby/(?!string\b|sym\b|symbol\b)[\w/]*:?([\w:]*)}
  OBJECT_VALUE = /\A\[object: [\w:]+\]\z/

  # A JSON object member: indent, "key", ": " and the rest (value, comma,
  # comment). The key part is kept verbatim; only the value is rewritten.
  JSON_MEMBER = /\A( *)("(?:[^"\\]|\\.)*")( *: *)(.*)\z/
  JSON_SCALAR = /\A(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][-+]?\d+)?|true|false|null)/

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
    flatten(parse(content), "", out, {})
    out
  end

  # Lines without the BOM and the \r of CRLF; written back as they were.
  def self.lines_of(content)
    content.delete_prefix("\uFEFF").split("\n", -1).map { |l| l.delete_suffix("\r") }
  end

  def self.parse(content)
    YAML.safe_load(readable(content), permitted_classes: [Symbol], aliases: true)
  end

  # Spinel's Psych can't build a Date, a Time or a Ruby object, even when
  # permitted: dates are read as text, and a !ruby/... node as "[object: X]".
  def self.readable(content)
    lines = LocaleFile.lines_of(content)
    out = []
    skip_deeper = -1
    in_block = false
    lines.each do |line|
      indent = line.length - line.lstrip.length
      if skip_deeper >= 0
        if line.strip.empty? || indent > skip_deeper
          out << (in_block ? line : "")
          next
        end
        skip_deeper = -1
      end
      if line.match?(/:(?: +&\S+)? +[|>][-+0-9]*(?: +#.*)?\z/) || line.match?(/\A\s*- +[|>][-+0-9]*\z/)
        out << line
        skip_deeper = indent
        in_block = true
        next
      end
      if (m = line.match(RUBY_TAG))
        name = m[2].empty? ? "Object" : m[2]
        out << "#{m[1]}\"[object: #{name}]\""
        skip_deeper = indent
        in_block = false
      elsif (m = line.match(DATE_VALUE))
        out << "#{m[1]}'#{m[2]}'"
      else
        out << line
      end
    end
    out.join("\n")
  end

  def entry(key)
    @entries.find { |e| e.key == key }
  end

  def json?
    @path.end_with?(".json")
  end

  # Raises if the rewritten file wouldn't load back with the new value and every
  # other value untouched; the file is only written after that check.
  def update(key, value)
    target = entry(key)
    raise ArgumentError, "#{key} not found in #{@path}" unless target
    raise ArgumentError, "#{key} can't be edited here" unless target.editable

    raw = File.read(@path)
    lines = LocaleFile.lines_of(raw)
    content = json? ? json_update(lines, target, key, value) : yaml_update(lines, target, value)
    write_checked(as_written(content, raw), key, value)
  end

  def yaml_update(lines, target, value)
    head = lines[target.line - 1].match(KEY_LINE)
    anchor = head[3].to_s[/\A&\S+ /].to_s
    replacement = scalar_lines("#{head[1]}#{head[2]}: #{anchor}".rstrip, head[1].length, value, target.style)
    (lines[0, target.line - 1] + replacement + lines[target.last_line..]).join("\n")
  end

  # JSON: replace only the value token, keeping the trailing comma, comments
  # and everything else on the line untouched.
  def json_update(lines, target, key, value)
    m = lines[target.line - 1].match(JSON_MEMBER)
    pair = nil
    pair = json_split_rest(m[4]) if m
    token = pair && pair[0]
    tail = pair && pair[1]
    raise ArgumentError, "#{key} can't be edited here" unless m && token

    replacement = "#{m[1]}#{m[2]}#{m[3]}#{json_quote(value)}#{tail}"
    (lines[0, target.line - 1] + [replacement] + lines[target.last_line..]).join("\n")
  end

  # Adds a key that isn't there, under its deepest existing parent, indented
  # like that parent's children; missing parents are created on the way.
  def insert(key, value)
    raise ArgumentError, @error unless @error.empty?
    raise ArgumentError, "#{key} already exists in #{@path}" if entry(key)

    raw = File.read(@path)
    lines = LocaleFile.lines_of(raw)
    content = json? ? json_insert(lines, key, value) : yaml_insert(lines, key, value)
    content += "\n" unless content.end_with?("\n")
    write_checked(as_written(content, raw), key, value)
  end

  def yaml_insert(lines, key, value)
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
    (lines[0, at] + added + lines[at..]).join("\n")
  end

  private

  # Splits a member's rest ("value, // comment") into the value token and
  # what follows it; [nil, nil] when it isn't a JSON scalar token.
  def json_split_rest(rest)
    stripped = rest.to_s.lstrip
    if stripped.start_with?('"')
      i = 1
      while i < stripped.length
        c = stripped[i]
        break if c == '"'

        i += c == "\\" ? 2 : 1
      end
      return [nil, nil] if i >= stripped.length

      return [stripped[0..i], stripped[(i + 1)..]]
    end
    m = stripped.match(JSON_SCALAR)
    return [nil, nil] unless m

    [m[0], stripped[m[0].length..]]
  end

  # A JSON string literal: double quotes, JSON escapes, raw UTF-8 kept.
  def json_quote(value)
    out = '"'.dup
    value.each_char do |c|
      if c == '"'
        out << '\\"'
      elsif c == "\\"
        out << "\\\\"
      elsif c == "\n"
        out << "\\n"
      elsif c == "\r"
        out << "\\r"
      elsif c == "\t"
        out << "\\t"
      elsif c.ord < 0x20
        out << "\\u" << c.ord.to_s(16).rjust(4, "0")
      else
        out << c
      end
    end
    out << '"'
  end

  # JSON: adds the missing chain under the deepest existing parent (or the
  # root), before the object's closing brace, commas in place.
  def json_insert(lines, key, value)
    positions = scan(lines)
    parts = key.split(".")
    depth = parts.size - 1
    depth -= 1 while depth.positive? && !positions.key?(parts[0, depth].join("."))

    braces = nil
    if depth.positive?
      parent = parts[0, depth].join(".")
      raise ArgumentError, "#{parent} has a value; #{key} can't go under it" if entry(parent)

      braces = json_braces(lines, positions[parent][0] - 1)
    else
      open_line = lines.index { |l| l.include?("{") }
      braces = open_line ? json_braces(lines, open_line) : [nil, nil, nil, nil]
    end
    open_line = braces[0]
    open_char = braces[1]
    close_line = braces[2]
    close_char = braces[3]
    return json_from_scratch(parts, value) unless open_line && close_line

    remaining = parts[depth..-1]
    if open_line == close_line
      json_insert_inline(lines, open_line, open_char, close_char, remaining, value)
      lines.join("\n")
    else
      indent = depth.positive? ? child_indent(positions, parts[0, depth].join(".")) : json_root_indent(positions)
      json_insert_block(lines, open_line, close_line, indent, remaining, value).join("\n")
    end
  end

  # The { on open_line and its matching }: [open line, open char, close line,
  # close char]; [nil, ...] when the object isn't closed. Braces inside
  # strings and comments don't count.
  def json_braces(lines, open_line)
    i = lines[open_line].index("{")
    return [nil, nil, nil, nil] unless i

    depth = 0
    (open_line...lines.size).each do |n|
      current = lines[n]
      j = n == open_line ? i : 0
      while j < current.length
        c = current[j]
        if c == '"'
          j += 1
          while j < current.length
            break if current[j] == '"'

            j += current[j] == "\\" ? 2 : 1
          end
        elsif c == "/" && current[j + 1] == "/"
          break
        elsif c == "/" && current[j + 1] == "*"
          while j < current.length
            if current[j] == "*" && current[j + 1] == "/"
              j += 1
              break
            end
            j += 1
          end
        elsif c == "{"
          depth += 1
        elsif c == "}"
          depth -= 1
          return [open_line, i, n, j] if depth.zero?
        end
        j += 1
      end
    end
    [nil, nil, nil, nil]
  end

  # { "a": 1 } on one line: the entry joins the flow, comma before it.
  def json_insert_inline(lines, line_no, open_char, close_char, parts, value)
    line = lines[line_no]
    inner = line[(open_char + 1)...close_char].rstrip
    if parts.size > 1
      key = Regexp.escape(json_quote(parts[0]))
      raise ArgumentError, "#{parts[0]} already exists here" if inner.match?(/(?:\A|,)\s*#{key}\s*:/)
    end
    if inner.empty?
      comma = ""
    else
      comma = ", "
    end
    lines[line_no] = line[0..open_char] + inner + comma + json_nested_value(parts, value) + " " + line[close_char..]
    lines
  end

  # Multi-line object: the chain goes before the closing brace, indented like
  # its siblings; the entry that becomes the previous one gains its comma.
  def json_insert_block(lines, open_line, close_line, indent, parts, value)
    step = 2
    added = []
    parts[0..-2].each_with_index do |part, i|
      added << "#{' ' * (indent + (i * step))}#{json_quote(part)}: {"
    end
    added << "#{' ' * (indent + ((parts.size - 1) * step))}#{json_quote(parts.last)}: #{json_quote(value)}"
    prev = json_previous_entry(lines, open_line, close_line)
    lines[prev] = json_ensure_comma(lines[prev]) if prev
    lines[0...close_line] + added + lines[close_line..]
  end

  # The entry line right before the closing brace, or nil when the object has
  # no entries (blank lines between the { and the } don't count).
  def json_previous_entry(lines, open_line, close_line)
    prev = close_line - 1
    prev -= 1 while prev > open_line && lines[prev].strip.empty?
    prev > open_line ? prev : nil
  end

  # Appends the separating comma a JSON member needs once it stops being the
  # last entry; the comma goes before a trailing comment.
  def json_ensure_comma(line)
    m = line.match(JSON_MEMBER)
    unless m
      stripped = line.rstrip
      return line if stripped.end_with?(",")

      return "#{line},"
    end
    pair = json_split_rest(m[4])
    token = pair[0]
    tail = pair[1]
    return "#{line}," unless token
    return line if tail.lstrip.start_with?(",")

    "#{m[1]}#{m[2]}#{m[3]}#{token},#{tail}"
  end

  # "a": { "b": { "c": "v" } } for the parts that aren't in the file yet.
  def json_nested_value(parts, value)
    out = "".dup
    parts[0..-2].each { |part| out << "#{json_quote(part)}: { " }
    out << "#{json_quote(parts.last)}: #{json_quote(value)}"
    out << (" }" * (parts.size - 1))
    out
  end

  def json_root_indent(positions)
    indents = []
    positions.each { |k, pos| indents << pos[3] unless k.include?(".") }
    indents.empty? ? 2 : indents.min
  end

  # A file without braces (an empty new one): the whole tree from the locale
  # down, pretty-printed with two-space indentation.
  def json_from_scratch(parts, value)
    out = ["{"]
    (0...(parts.size - 1)).each { |i| out << "#{' ' * (2 * (i + 1))}#{json_quote(parts[i])}: {" }
    out << "#{' ' * (2 * parts.size)}#{json_quote(parts.last)}: #{json_quote(value)}"
    (parts.size - 2).downto(0) do |i|
      pad = " " * (2 * (i + 1))
      out << pad + "}"
    end
    out << "}"
    out.join("\n")
  end

  def as_written(content, raw)
    out = raw.include?("\r\n") ? content.gsub("\n", "\r\n") : content
    raw.start_with?("\uFEFF") ? "\uFEFF#{out}" : out
  end

  def write_checked(content, key, value)
    expected = {}
    @entries.each { |e| expected[e.key] = e.value }
    expected[key] = value
    actual = {}
    begin
      LocaleFile.flatten(LocaleFile.parse(content), "", actual, {})
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
      LocaleFile.flatten(LocaleFile.parse(content), "", values, complex)
    rescue StandardError => e
      @error = e.message
      return
    end
    lines = LocaleFile.lines_of(content)
    positions = scan(lines)
    values.each do |key, value|
      pos = positions[key]
      editable = !pos.nil? && !complex.key?(key)
      editable = false if editable && value.match?(OBJECT_VALUE) && lines[pos[0] - 1].include?("!ruby/")
      if editable && json?
        m = lines[pos[0] - 1].match(JSON_MEMBER)
        pair = nil
        pair = json_split_rest(m[4]) if m
        editable = !m.nil? && !pair.nil? && !pair[0].nil?
      end
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
      if rest.empty? || rest.start_with?("#") || (json? && rest.start_with?("{", "["))
        # An empty value owns no deeper content the way a block scalar does;
        # children below keep their own lines. In JSON the same goes for flow
        # openers ({, [), whose children are regular object members. YAML
        # flow openers keep the old behavior: their lines stay unclaimed, so
        # those keys remain read-only.
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
