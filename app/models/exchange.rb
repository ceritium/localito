# CSV (key + one column per locale) and XLIFF 1.2 (one source and one target
# locale) for translators, and reading either back as [name, locale, value].
class Exchange
  XML_ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;" }.freeze
  XML_ENTITIES = { "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'" }.freeze

  # A missing cell and an empty value are both an empty field; importing
  # skips empty fields, so a round trip never creates empty translations.
  def self.csv(t, names, locales)
    out = +""
    out << csv_line(["key"] + locales)
    names.each do |name|
      out << csv_line([name] + locales.map { |locale| t.value(name, locale).to_s })
    end
    out
  end

  def self.csv_line(fields)
    fields.map { |f| csv_field(f) }.join(",") + "\n"
  end

  def self.csv_field(value)
    return value unless value.match?(/[",\r\n]/) || value != value.strip

    "\"#{value.gsub('"', '""')}\""
  end

  def self.xliff(t, names, source, target)
    out = +""
    out << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    out << "<xliff version=\"1.2\" xmlns=\"urn:oasis:names:tc:xliff:document:1.2\">\n"
    out << "  <file original=\"localito\" source-language=\"#{xml(source)}\" target-language=\"#{xml(target)}\" datatype=\"plaintext\">\n"
    out << "    <body>\n"
    names.each do |name|
      from = t.value(name, source)
      next if from.nil? || from.empty?

      to = t.value(name, target)
      state = to.nil? || to.empty? ? "needs-translation" : "translated"
      out << "      <trans-unit id=\"#{xml(name)}\" resname=\"#{xml(name)}\">\n"
      out << "        <source>#{xml(from)}</source>\n"
      out << "        <target state=\"#{state}\">#{xml(to.to_s)}</target>\n"
      out << "      </trans-unit>\n"
    end
    out << "    </body>\n  </file>\n</xliff>\n"
    out
  end

  def self.xml(value)
    value.gsub(/[&<>"]/) { |c| XML_ESCAPES[c] }
  end

  # [[name, locale, value], ...] from CSV or XLIFF text; empty values skipped.
  def self.parse(text)
    text = text.delete_prefix("﻿")
    rows = text.lstrip.start_with?("<") ? parse_xliff(text) : parse_csv(text)
    rows.reject { |row| row[2].empty? }
  end

  def self.parse_xliff(text)
    rows = []
    files = text.scan(%r{<file\b([^>]*)>(.*?)</file>}m)
    raise ArgumentError, "No <file> element: is this XLIFF 1.2?" if files.empty?

    files.each do |attrs, body|
      locale = attrs[/target-language="([^"]*)"/, 1].to_s
      raise ArgumentError, "A <file> has no target-language" if locale.empty?

      body.scan(%r{<trans-unit\b([^>]*)>(.*?)</trans-unit>}m).each do |unit_attrs, unit|
        name = unxml(unit_attrs[/\bid="([^"]*)"/, 1].to_s)
        target = unit[%r{<target\b[^>]*>(.*?)</target>}m, 1].to_s
        rows << [name, locale, unxml(target)]
      end
    end
    rows
  end

  def self.unxml(value)
    value.gsub(/&(#x[0-9a-fA-F]+|#\d+|\w+);/) do
      ref = Regexp.last_match(1)
      if ref.start_with?("#x")
        [ref[2..].to_i(16)].pack("U")
      elsif ref.start_with?("#")
        [ref[1..].to_i].pack("U")
      else
        XML_ENTITIES[ref] || "&#{ref};"
      end
    end
  end

  def self.parse_csv(text)
    records = csv_records(text)
    raise ArgumentError, "Empty CSV" if records.empty?

    header = records.first
    raise ArgumentError, "The first column must be \"key\"" unless header.first.to_s.strip == "key"

    locales = header.drop(1).map(&:strip)
    rows = []
    records.drop(1).each do |record|
      name = record.first.to_s.strip
      next if name.empty?

      locales.each_with_index { |locale, i| rows << [name, locale, record[i + 1].to_s] }
    end
    rows
  end

  # RFC 4180: quoted fields may hold commas, quotes ("") and newlines.
  def self.csv_records(text)
    records = []
    fields = []
    field = +""
    quoted = false
    i = 0
    while i < text.length
      c = text[i]
      if quoted
        if c == '"' && text[i + 1] == '"'
          field << '"'
          i += 1
        elsif c == '"'
          quoted = false
        else
          field << c
        end
      elsif c == '"'
        quoted = true
      elsif c == ","
        fields << field
        field = +""
      elsif c == "\n" || c == "\r"
        i += 1 if c == "\r" && text[i + 1] == "\n"
        fields << field
        records << fields unless fields.size == 1 && fields.first.empty?
        fields = []
        field = +""
      else
        field << c
      end
      i += 1
    end
    fields << field
    records << fields unless fields.size == 1 && fields.first.empty?
    records
  end
end
