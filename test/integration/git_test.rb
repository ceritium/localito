require_relative "../support/sample_app"

class GitTest < Spinrail::IntegrationTest
  include SampleApp

  def test_without_git_nothing_is_compared
    get "/"
    refute_includes response.body, "comparing with"
    refute_includes response.body, %(value="changed")
  end

  def test_shows_uncommitted_changes_against_head
    git_init
    write_locale("es.yml", locale_file("es.yml").sub('"Hola"', '"Buenas"') + "  added_now: Nueva\n")
    write_locale("en.yml", locale_file("en.yml").sub("  only_en: Only in English\n", ""))

    get "/?filter=changed"
    assert_includes response.body, "comparing with <strong>HEAD</strong>"
    names = response.body.scan(%r{<th class="key" scope="row"><a [^>]*>([^<]+)</a>}).flatten
    assert_equal %w[added_now hello only_en], names
    assert_match %r{class="cell modified"[^>]*data-cell="es.hello"}, response.body
    assert_includes response.body, %(<div class="base" title="At the base">Hola</div>)

    get "/diff"
    assert_includes response.body, "3 changes"
    assert_includes response.body, %(<span class="badge removed">removed</span>)
  end

  def test_typed_ref_stays_selected
    git_init
    get "/?base=HEAD~0"
    assert_includes response.body, "comparing with <strong>HEAD~0</strong>"
    assert_includes response.body, %(<option value="HEAD~0" selected>vs HEAD~0</option>)
    assert_includes response.body, %(data-combo data-free>)
  end

  def test_compare_with_a_branch
    git_init
    git("checkout", "-q", "-b", "feature")
    write_locale("es.yml", locale_file("es.yml").sub('"Hola"', '"Buenas"'))
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qam", "change")

    get "/?filter=changed"
    refute_includes response.body, %(data-cell="es.hello")
    get "/?filter=changed&base=main"
    assert_includes response.body, "comparing with <strong>main</strong>"
    assert_includes response.body, %(data-cell="es.hello")
  end
end
