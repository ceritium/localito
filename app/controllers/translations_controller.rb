class TranslationsController < ApplicationController
  def index
    @translations = Translations.new(root)
    @query = params[:q].to_s
    @missing = params[:missing].to_s == "1"
    @names = @translations.search(@query, @missing)
  end

  def edit
    @translations = Translations.new(root)
    @name = params[:name].to_s
    @locale = params[:locale].to_s
    @entry = @translations.cell(@name, @locale)
    @value = @entry ? @entry.value : ""
    @query = params[:q].to_s
    @error = ""
    if @entry.nil? || !@entry.editable
      render plain: "Not found", status: :not_found
    end
  end

  def update
    @translations = Translations.new(root)
    @name = params[:name].to_s
    @locale = params[:locale].to_s
    @entry = @translations.cell(@name, @locale)
    @value = params[:value].to_s.gsub("\r\n", "\n")
    @query = params[:q].to_s
    @error = ""
    if @entry.nil? || !@entry.editable
      render plain: "Not found", status: :not_found
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

  private

  def root
    ENV["LOCALITO_ROOT"] || "."
  end
end
