require_relative "../support/sample_app"

class ConfigTest < Spinrail::IntegrationTest
  include SampleApp

  def test_header_says_which_config
    get "/"
    assert_includes response.body, %(<a href="/config">default config</a>)
    write_config("base: HEAD\n")
    get "/"
    assert_includes response.body, %(<a href="/config">config: .localito.yml</a>)
  end

  def test_config_page_shows_settings_and_files
    write_config("readonly:\n  - config/locales/devise/**\n")
    get "/config"
    assert_response :success
    assert_includes response.body, "<code>config/locales/**/*.yml</code>"
    assert_includes response.body, "<code>config/locales/devise/**</code>"
    assert_match %r{config/locales/devise/en.yml</a></th>\s*<td>en</td>\s*<td>1</td>\s*<td>\s*<span class="badge">read-only</span>}, response.body
  end

  def test_exclude_leaves_files_out
    write_config("exclude:\n  - config/locales/devise/*\n")
    get "/"
    refute_includes response.body, "devise.failure.locked"
    assert_includes response.body, "posts.index.title"
  end

  def test_readonly_files_are_shown_but_not_written
    write_config("readonly:\n  - config/locales/es.yml\n")
    get "/"
    assert_equal "0", cell_attrs("hello", "es")["editable"]
    assert_equal "0", cell_attrs("only_en", "es")["editable"]
    assert_equal "1", cell_attrs("hello", "en")["editable"]
    before = locale_file("es.yml")
    patch "/translation", params: { name: "hello", locale: "es", value: "Buenas", inline: "1", original: "Hola", was_missing: "0" }
    assert_response :unprocessable_entity
    assert_equal before, locale_file("es.yml")
  end

  def test_default_locale_comes_first_and_is_the_reference
    write_config("default_locale: es\n")
    get "/"
    assert_match %r{<th>es</th>\s*<th>en</th>}, response.body
    assert_includes response.body, "Placeholders differ from es"
  end

  def test_new_keys_pattern
    write_config(%(new_keys: "config/locales/new/%{locale}.yml"\n))
    post "/keys", params: { name: "brand.new", value_locales: ["en"], values: ["Fresh"] }
    assert_equal({ "en" => { "brand" => { "new" => "Fresh" } } }, loaded("new/en.yml"))
  end

  def test_new_keys_without_locale_is_an_error
    write_config(%(new_keys: "config/locales/all.yml"\n))
    get "/"
    assert_includes response.body, "new_keys needs %{locale} in it"
  end
end

class ConfigPathTest < Spinrail::IntegrationTest
  include SampleApp

  def setup
    @config_dir = Dir.mktmpdir("localito-config")
    File.write(File.join(@config_dir, "elsewhere.yml"), "locales: [es, en]\n")
    super
  end

  def teardown
    super
    FileUtils.rm_rf(@config_dir)
  end

  def test_config_from_another_path
    get "/"
    assert_includes response.body, "config: #{@config_dir}/elsewhere.yml"
    assert_match %r{<th>es</th>\s*<th>en</th>}, response.body
  end

  private

  def config_env
    File.join(@config_dir, "elsewhere.yml")
  end
end
