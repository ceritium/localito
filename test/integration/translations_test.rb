require "fileutils"
require "tmpdir"
require "yaml"

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
    patch "/translation", params: { name: "posts.index.title", locale: "en", value: "Articles" }
    assert_response :redirect
    after = locale_file("en.yml")
    assert_equal before.sub("title: Posts # inline comment", "title: Articles"), after
  end

  def test_edit_keeps_quoting_style
    patch "/translation", params: { name: "hello", locale: "es", value: "Hola \"tú\"" }
    assert_includes locale_file("es.yml"), %(  hello: "Hola \\"tú\\"")
    patch "/translation", params: { name: "quoted", locale: "en", value: "Isn't it" }
    assert_includes locale_file("en.yml"), "  quoted: 'Isn''t it'"
  end

  def test_plain_value_that_yaml_would_retype_gets_quoted
    patch "/translation", params: { name: "posts.index.title", locale: "es", value: "yes" }
    assert_equal "yes", YAML.safe_load(locale_file("es.yml")).dig("es", "posts", "index", "title")
  end

  def test_edit_block_scalar
    patch "/translation", params: { name: "intro", locale: "en", value: "One.\nTwo.\nThree.\n" }
    assert_includes locale_file("en.yml"), "  intro: |\n    One.\n    Two.\n    Three.\n  folded:"
    patch "/translation", params: { name: "folded", locale: "es", value: "Una sola línea" }
    assert_equal "Una sola línea", YAML.safe_load(locale_file("es.yml")).dig("es", "folded")
  end

  def test_every_edit_round_trips
    patch "/translation", params: { name: "greeting", locale: "en", value: "Hi: %{name} # not a comment" }
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
    patch "/translation", params: { name: "devise.failure.locked", locale: "en", value: "Locked." }
    assert_includes locale_file("devise/en.yml"), %(locked: "Locked.")
  end

  def test_edit_that_would_corrupt_the_file_is_refused
    before = locale_file("es.yml")
    patch "/translation", params: { name: "next_line", locale: "es", value: "Otro" }
    assert_response :unprocessable_entity
    assert_includes response.body, "would change other values"
    assert_equal before, locale_file("es.yml")
  end

  private

  def locale_file(name)
    File.read(File.join(@app_root, "config/locales", name))
  end
end
