require_relative "../support/sample_app"

class ChecksTest < Spinrail::IntegrationTest
  include SampleApp

  def test_file_tree_and_scope
    get "/"
    assert_includes response.body, %(title="config/locales/*.yml")
    assert_includes response.body, %(title="config/locales/devise/*.yml")
    get "/?file=#{CGI.escape('config/locales/devise/*.yml')}"
    assert_includes response.body, "devise.failure.locked"
    refute_includes response.body, "posts.index.title"
    assert_includes response.body, "1 key in <strong>config/locales/devise/*.yml</strong>"
    get "/?file=#{CGI.escape('config/locales/')}"
    assert_includes response.body, "devise.failure.locked"
    assert_includes response.body, "posts.index.title"
  end

  def test_suffixed_files_group_across_locales
    write_locale("admin.en.yml", "en:\n  admin:\n    title: Admin\n")
    write_locale("admin.es.yml", "es:\n  admin:\n    title: Administración\n")
    get "/?file=#{CGI.escape('config/locales/admin.*.yml')}"
    assert_includes response.body, "1 key in"
    assert_includes response.body, "Administración"
  end

  def test_duplicates_are_flagged
    write_locale("extra.en.yml", "en:\n  hello: Hi there\n")
    get "/"
    assert_includes response.body, "1 key is defined in more than one file"
    assert_includes response.body, "defined in 2 files; the first wins"
    get "/?filter=duplicated"
    assert_includes response.body, "1 key."
    get "/key?name=hello"
    assert_includes response.body, "used: config/locales/en.yml:3"
    assert_includes response.body, "ignored: config/locales/extra.en.yml:2"
  end

  def test_interpolation_mismatch
    save("greeting", "es", "Hola")
    save("posts.count.other", "es", "%{total} entradas")
    get "/?filter=interpolation"
    assert_includes response.body, "2 keys."
    assert_includes response.body, "missing %{name}"
    assert_includes response.body, "missing %{count}, %{total} isn&#39;t in en"
  end
end
