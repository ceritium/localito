require "fileutils"
require "tmpdir"
require "yaml"
require "cgi"

class TranslationsTest < Spinrail::IntegrationTest
  SAMPLE = File.expand_path("../sample_app", __dir__)

  def setup
    @app_root = Dir.mktmpdir("localito-test")
    FileUtils.cp_r("#{SAMPLE}/.", @app_root)
    self.class.server_env("LOCALITO_ROOT" => @app_root)
    super
  end

  def teardown
    super
    FileUtils.rm_rf(@app_root)
  end

  def test_lists_keys_by_locale
    get "/"
    assert_response :success
    assert_includes response.body, "posts.index.title"
    assert_includes response.body, "Entradas"
    assert_includes response.body, "devise.failure.locked"
    assert_includes response.body, "Sunday, Monday"
  end

  def test_missing_only
    get "/?missing=1"
    assert_includes response.body, "only_en"
    assert_includes response.body, "devise.failure.locked"
    refute_includes response.body, "posts.index.title"
  end

  def test_search_by_value
    get "/?q=entradas"
    assert_includes response.body, "posts.index.title"
    refute_includes response.body, "greeting"
  end

  def test_edit_keeps_the_rest_of_the_file
    before = locale_file("en.yml")
    save("posts.index.title", "en", "Articles")
    assert_response :redirect
    after = locale_file("en.yml")
    assert_equal before.sub("title: Posts # inline comment", "title: Articles"), after
  end

  def test_edit_keeps_quoting_style
    save("hello", "es", "Hola \"tú\"")
    assert_includes locale_file("es.yml"), %(  hello: "Hola \\"tú\\"")
    save("quoted", "en", "Isn't it")
    assert_includes locale_file("en.yml"), "  quoted: 'Isn''t it'"
  end

  def test_plain_value_that_yaml_would_retype_gets_quoted
    save("posts.index.title", "es", "yes")
    assert_equal "yes", YAML.safe_load(locale_file("es.yml")).dig("es", "posts", "index", "title")
  end

  def test_edit_block_scalar
    save("intro", "en", "One.\nTwo.\nThree.\n")
    assert_includes locale_file("en.yml"), "  intro: |\n    One.\n    Two.\n    Three.\n  folded:"
    save("folded", "es", "Una sola línea")
    assert_equal "Una sola línea", YAML.safe_load(locale_file("es.yml")).dig("es", "folded")
  end

  def test_every_edit_round_trips
    save("greeting", "en", "Hi: %{name} # not a comment")
    data = YAML.safe_load(locale_file("en.yml"))
    assert_equal "Hi: %{name} # not a comment", data.dig("en", "greeting")
    assert_equal "Hello", data.dig("en", "hello")
    assert_equal ["Sunday", "Monday"], data.dig("en", "date", "day_names")
  end

  def test_arrays_are_read_only
    get "/translation/edit?name=date.day_names&locale=en"
    assert_response :not_found
  end

  def test_nested_file
    save("devise.failure.locked", "en", "Locked.")
    assert_includes locale_file("devise/en.yml"), %(locked: "Locked.")
  end

  def test_edit_that_would_corrupt_the_file_is_refused
    before = locale_file("es.yml")
    save("next_line", "es", "Otro")
    assert_response :unprocessable_entity
    assert_includes response.body, "would change other values"
    assert_equal before, locale_file("es.yml")
  end

  def test_picks_up_files_changed_on_disk
    get "/?q=posts.index.title"
    assert_includes response.body, "Entradas"
    File.write(File.join(@app_root, "config/locales/es.yml"), locale_file("es.yml").sub("title: Entradas", "title: Artículos"))
    get "/?q=posts.index.title"
    assert_includes response.body, "Artículos"
  end

  def test_config_orders_locales_and_sets_paths
    FileUtils.mkdir_p(File.join(@app_root, "other"))
    File.write(File.join(@app_root, "other/fr.yml"), "fr:\n  hello: Bonjour\n")
    File.write(File.join(@app_root, ".localito.yml"), "paths:\n  - config/locales/*.yml\n  - other/*.yml\nlocales: [fr, es]\n")
    get "/"
    assert_includes response.body, "Bonjour"
    refute_includes response.body, "devise.failure.locked"
    headers = response.body.scan(%r{<th>(\w+)</th>}).flatten
    assert_equal %w[Key fr es en], headers
  end

  def test_broken_config_is_reported
    File.write(File.join(@app_root, ".localito.yml"), "paths: [unclosed\n")
    get "/"
    assert_response :success
    assert_includes response.body, ".localito.yml:"
  end

  def test_changes_reports_a_new_version_when_a_file_changes
    get "/changes"
    before = response.body
    get "/changes"
    assert_equal before, response.body
    File.write(File.join(@app_root, "config/locales/fr.yml"), "fr:\n  hello: Bonjour\n")
    get "/changes"
    refute_equal before, response.body
  end

  def test_save_over_a_value_changed_on_disk_is_refused
    get "/translation/edit?name=hello&locale=es"
    original = original_value
    File.write(File.join(@app_root, "config/locales/es.yml"), locale_file("es.yml").sub('"Hola"', '"Buenas"'))
    patch "/translation", params: { name: "hello", locale: "es", value: "Hey", original: original }
    assert_response :conflict
    assert_includes locale_file("es.yml"), '"Buenas"'
    assert_equal "Buenas", original_value
    patch "/translation", params: { name: "hello", locale: "es", value: "Hey", original: original_value }
    assert_response :redirect
    assert_includes locale_file("es.yml"), '"Hey"'
  end

  def test_pages_load_the_live_script
    get "/"
    assert_includes response.body, 'id="live"'
    assert_match %r{<script src="/live-\w+\.js" defer}, response.body
  end

  private

  def save(name, locale, value)
    get "/translation/edit?name=#{CGI.escape(name)}&locale=#{locale}"
    patch "/translation", params: { name: name, locale: locale, value: value, original: original_value }
  end

  def original_value
    CGI.unescapeHTML(response.body[/name="original" value="([^"]*)"/m, 1])
  end

  def locale_file(name)
    File.read(File.join(@app_root, "config/locales", name))
  end
end
