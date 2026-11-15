class TranslationsController < ApplicationController
  LIMIT = 500

  before_action :prepare, except: [:version]

  def index
    @query = params[:q].to_s
    @filter = params[:filter].to_s
    found = @translations.search(@query, @filter, @visible)
    @total = found.size
    @names = found.first(LIMIT)
    @stats = @translations.stats
  end

  def show
    @name = params[:name].to_s
    @query = params[:q].to_s
    @filter = params[:filter].to_s
    render plain: "Not found", status: :not_found unless @translations.names.include?(@name)
  end

  def update
    @name = params[:name].to_s
    @locale = params[:locale].to_s
    value = params[:value].to_s.gsub("\r\n", "\n")
    original = params[:original].to_s.gsub("\r\n", "\n")
    begin
      @translations.set(@name, @locale, value, original, params[:was_missing].to_s == "1")
    rescue Translations::Conflict => e
      render plain: "#{e.message}. Reload to see it.", status: :conflict
      return
    rescue ArgumentError => e
      render plain: e.message, status: :unprocessable_entity
      return
    end
    if params[:inline].to_s == "1"
      head :ok
    else
      redirect_to key_path(name: @name)
    end
  end

  def new
    @name = params[:name].to_s
    @values = {}
    @error = ""
  end

  def create
    @name = params[:name].to_s.strip
    @values = {}
    sent_locales = params.fetch(:value_locales, [])
    sent_values = params.fetch(:values, [])
    sent_locales.each_with_index do |locale, i|
      @values[locale.to_s] = sent_values[i].to_s.gsub("\r\n", "\n") if @translations.locales.include?(locale.to_s)
    end
    @error = ""
    if !@name.match?(Translations::KEY_NAME)
      @error = "Write the key as dot-separated parts, without spaces: posts.index.title"
    elsif @translations.names.include?(@name)
      @error = "#{@name} already exists"
    elsif @values.values.all?(&:empty?)
      @error = "Give it a value in at least one locale"
    end
    unless @error.empty?
      render :new, status: :unprocessable_entity
      return
    end
    begin
      @values.each { |locale, value| @translations.add(@name, locale, value) unless value.empty? }
    rescue ArgumentError => e
      @error = e.message
      render :new, status: :unprocessable_entity
      return
    end
    redirect_to key_path(name: @name)
  end

  def diff
    @changes = @translations.changes
  end

  def version
    render plain: Translations.version(root)
  end

  private

  def root
    ENV["LOCALITO_ROOT"] || "."
  end

  # Layout, visible locales and base ref stick in the session once chosen.
  def prepare
    @translations = Translations.load(root)
    session[:layout] = params[:layout].to_s if %w[table list].include?(params[:layout].to_s)
    session[:locales] = params.fetch(:locales, []).join(",") if params[:locales_set].to_s == "1"
    session[:base] = params[:base].to_s unless params[:base].to_s.empty?
    @layout = session[:layout].to_s == "list" ? "list" : "table"

    @repo = GitBase.repo?(root)
    @base_ref = session[:base].to_s.empty? ? @translations.config.base : session[:base].to_s
    @base_error = ""
    @branches = []
    @current_branch = ""
    if @repo
      base = GitBase.new(root, @base_ref, @translations.config.paths)
      @base_error = base.error
      @translations.compare(base.available? ? base.sha : "", base.values)
      @branches = GitBase.branches(root)
      @current_branch = GitBase.current_branch(root)
    end

    chosen = session[:locales].to_s.split(",")
    @visible = @translations.locales.select { |l| chosen.include?(l) }
    @visible = @translations.locales if @visible.empty?
    @version = Translations.version(root)
  end
end
