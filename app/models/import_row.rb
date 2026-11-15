# One value of an import: status is "new", "changed", "same" or "error".
class ImportRow
  attr_reader :name, :locale, :value, :current, :status, :message

  def initialize(name, locale, value, current, status, message)
    @name = name
    @locale = locale
    @value = value
    @current = current
    @status = status
    @message = message
  end

  def missing?
    @status == "new"
  end
end
