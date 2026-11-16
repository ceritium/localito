class TranslationsController < ApplicationController
  LIMIT = 500

  before_action :prepare, except: [:version]

  def index
    found = @translations.search(@query, @filter, @visible, @scope)
    @total = found.size
    @names = found.first(LIMIT)
    @stats = @translations.stats
    @tree = @translations.tree(@visible)
    ref = @translations.reference
    missing_in = @filter.start_with?("missing:") ? @filter.delete_prefix("missing:") : ""
    others = (@visible + @translations.locales).reject { |l| l == ref }
    @export_target = missing_in.empty? || missing_in == ref ? others.first.to_s : missing_in
  end

  # The keys the list shows (search, filter, file), all of them.
  def export
    names = @translations.search(@query, @filter, @visible, @scope)
    if params[:format].to_s == "xliff"
      source = params[:source].to_s.empty? ? @translations.reference : params[:source].to_s
      target = params[:target].to_s
      unless @translations.locales.include?(source) && @translations.locales.include?(target) && target != source
        render plain: "Pick two different locales", status: :unprocessable_entity
        return
      end
      send_data Exchange.xliff(@translations, names, source, target), type: "application/x-xliff+xml",
                                                                      filename: "localito-#{source}-#{target}.xlf"
    else
      send_data Exchange.csv(@translations, names, @visible), type: "text/csv", filename: "localito.csv"
    end
  end

  def import
    @text = ""
    @rows = []
    @error = ""
    @result = ""
  end

  def preview_import
    @text = params[:text].to_s
    @rows = []
    @error = ""
    @result = ""
    begin
      @rows = @translations.preview_import(Exchange.parse(@text))
      @error = "Nothing to import: every value is empty" if @rows.empty?
    rescue ArgumentError => e
      @error = e.message
    end
    render :import
  end

  def apply_import
    names = params.fetch(:names, [])
    locales = params.fetch(:locales_in, [])
    values = params.fetch(:values, [])
    originals = params.fetch(:originals, [])
    missings = params.fetch(:missings, [])
    picks = params.fetch(:picks, []).map(&:to_s)
    applied = 0
    failed = []
    names.each_with_index do |name, i|
      next unless picks.include?(i.to_s)

      begin
        @translations.set(name.to_s, locales[i].to_s, values[i].to_s, originals[i].to_s, missings[i].to_s == "1")
        applied += 1
      rescue Translations::Conflict, ArgumentError => e
        failed << "#{locales[i]}.#{name}: #{e.message}"
      end
    end
    @text = ""
    @rows = []
    @error = failed.join("\n")
    @result = "#{applied} #{applied == 1 ? 'value' : 'values'} written."
    render :import
  end

  def settings
    @files = @translations.files
  end

  def show
    @name = params[:name].to_s
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
    @query = params[:q].to_s
    @filter = params[:filter].to_s
    @scope = params[:file].to_s
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
      base = GitBase.new(root, @base_ref, @translations.config.paths, @translations.config.exclude)
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
