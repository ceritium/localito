class LocaleEntry
  attr_reader :path, :key, :value, :line, :last_line, :style, :editable

  def initialize(path, key, value, line, last_line, style, editable)
    @path = path
    @key = key
    @value = value
    @line = line
    @last_line = last_line
    @style = style
    @editable = editable
  end

  def locale
    @key.split(".").first.to_s
  end

  # The key without its locale: "posts.index.title".
  def name
    @key.split(".").drop(1).join(".")
  end
end
