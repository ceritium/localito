require_relative "../support/sample_app"

class BrowseTest < Spinrail::IntegrationTest
  include SampleApp

  def test_lists_keys_by_locale
    get "/"
    assert_response :success
    assert_includes response.body, "posts.index.title"
    assert_includes response.body, "Entradas"
    assert_includes response.body, "devise.failure.locked"
    assert_includes response.body, "Sunday, Monday"
  end

  def test_stats_per_locale
    get "/"
    # 14 keys; es lacks devise.failure.locked and only_en, en lacks next_line.
    assert_match %r{<strong>es</strong><span>85%</span>}, response.body
    assert_includes response.body, "12/14 · 2 missing"
    assert_includes response.body, "13/14 · 1 missing"
  end

  def test_missing_filters
    get "/?filter=missing"
    assert_includes response.body, "only_en"
    assert_includes response.body, "next_line"
    refute_includes response.body, "posts.index.title"

    get "/?filter=missing:es"
    assert_includes response.body, "only_en"
    refute_includes response.body, "next_line"
  end

  def test_empty_filter
    write_locale("es.yml", locale_file("es.yml") + "  blank: \"\"\n")
    get "/?filter=empty"
    assert_includes response.body, "blank"
    refute_includes response.body, "only_en"
  end

  def test_search_by_value
    get "/?q=entradas"
    assert_includes response.body, "posts.index.title"
    refute_includes response.body, "greeting"
  end

  def test_layout_and_visible_locales_stick
    get "/?layout=list&locales_set=1&locales[]=es"
    assert_includes response.body, %(class="list")
    assert_includes response.body, "Locales 1/2"
    get "/"
    assert_includes response.body, %(class="list")
    refute_includes response.body, %(data-cell="en.hello")
    assert_includes response.body, %(data-cell="es.hello")
  end

  def test_key_page_shows_every_locale_and_where_a_missing_one_goes
    get "/key?name=only_en"
    assert_includes response.body, "Only in English"
    assert_includes response.body, %(data-cell="es.only_en")
    assert_includes response.body, "would go to config/locales/es.yml"
  end

  def test_version_changes_when_a_file_changes
    get "/version"
    before = response.body
    get "/version"
    assert_equal before, response.body
    write_locale("fr.yml", "fr:\n  hello: Bonjour\n")
    get "/version"
    refute_equal before, response.body
  end

  def test_picks_up_files_changed_on_disk
    get "/?q=posts.index.title"
    assert_includes response.body, "Entradas"
    write_locale("es.yml", locale_file("es.yml").sub("title: Entradas", "title: Artículos"))
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
    assert_equal %w[fr es en], response.body.scan(%r{<th>(\w+)</th>}).flatten
  end

  def test_broken_config_is_reported
    File.write(File.join(@app_root, ".localito.yml"), "paths: [unclosed\n")
    get "/"
    assert_response :success
    assert_includes response.body, ".localito.yml:"
  end

  def test_pages_load_the_live_script
    get "/"
    assert_includes response.body, 'id="live"'
    assert_match %r{<script src="/live-\w+\.js" defer}, response.body
  end

  def test_filter_select_and_clear
    get "/"
    refute_includes response.body, %(value="missing:es")
    refute_includes response.body, ">Clear</a>"
    get "/?q=posts&filter=missing:es"
    assert_includes response.body, %(<option value="missing:es" selected>Missing in es</option>)
    assert_includes response.body, ">Clear</a>"
  end
end
