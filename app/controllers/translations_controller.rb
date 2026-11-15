class TranslationsController < ApplicationController
  LIMIT = 500

  def index
    @translations = Translations.load(root)
    @query = params[:q].to_s
    @missing = params[:missing].to_s == "1"
    found = @translations.search(@query, @missing)
    @total = found.size
    @names = found.first(LIMIT)
    @version = Translations.version(root)
  end

  def edit
    @translations = Translations.load(root)
    @name = params[:name].to_s
    @locale = params[:locale].to_s
    @entry = @translations.cell(@name, @locale)
    @value = @entry ? @entry.value : ""
    @original = @value
    @query = params[:q].to_s
    @error = ""
    @version = Translations.version(root)
    if @entry.nil? || !@entry.editable
      render plain: "Not found", status: :not_found
    end
  end

  def update
    @translations = Translations.load(root)
    @name = params[:name].to_s
    @locale = params[:locale].to_s
    @entry = @translations.cell(@name, @locale)
    @value = params[:value].to_s.gsub("\r\n", "\n")
    @original = params[:original].to_s.gsub("\r\n", "\n")
    @query = params[:q].to_s
    @error = ""
    @version = Translations.version(root)
    if @entry.nil? || !@entry.editable
      render plain: "Not found", status: :not_found
      return
    end
    if @entry.value != @original
      @error = "This value changed on disk since you opened it. It is now shown below; save again to replace it."
      @original = @entry.value
      render :edit, status: :conflict
      return
    end
    begin
      @translations.file(@entry.path).update(@entry.key, @value)
    rescue ArgumentError => e
      @error = e.message
      render :edit, status: :unprocessable_entity
      return
    end
    redirect_to root_path(q: @query)
  end

  def changes
    render plain: Translations.version(root)
  end

  private

  def root
    ENV["LOCALITO_ROOT"] || "."
  end
end
