require_relative "../support/sample_app"

class ExchangeTest < Spinrail::IntegrationTest
  include SampleApp

  def test_csv_export_follows_the_list
    get "/export?format=csv&q=posts"
    assert_response :success
    assert_equal <<~CSV, response.body
      key,en,es
      posts.count.one,One post,Una entrada
      posts.count.other,%{count} posts,%{count} entradas
      posts.index.empty,No posts yet,Aún no hay entradas
      posts.index.title,Posts,Entradas
    CSV
    get "/export?format=csv&q=intro"
    assert_includes response.body, %(intro,"First line.\nSecond line.\n","Primera línea.)
  end

  def test_xliff_export
    get "/export?format=xliff&target=es&filter=missing"
    assert_response :success
    assert_includes response.body, %(source-language="en" target-language="es")
    assert_includes response.body, %(<trans-unit id="only_en" resname="only_en">\n        <source>Only in English</source>\n        <target state="needs-translation"></target>)
    refute_includes response.body, "next_line"
    get "/export?format=xliff&target=en"
    assert_response :unprocessable_entity
    get "/export?format=xliff&source=es&target=en&q=next_line"
    assert_includes response.body, %(source-language="es" target-language="en")
    assert_includes response.body, "<source>Valor en la línea siguiente</source>"
  end

  def test_export_menu_carries_the_current_filters
    get "/?q=posts&filter=missing:es&file=config/locales/*.yml"
    form = response.body[%r{<form action="/export".*?</form>}m]
    assert_includes form, %(name="q" value="posts")
    assert_includes form, %(name="filter" value="missing:es")
    assert_includes form, %(name="file" value="config/locales/*.yml")
    assert_includes form, %(<option value="es" selected>es</option>)
  end

  def test_csv_import_previews_then_writes
    csv = %(key,en,es\nhello,Hello,"Hola, ""amigo"""\nonly_en,,Solo en inglés\nbad key,x,y\n)
    post "/import", params: { text: csv }
    assert_response :success
    assert_includes response.body, "1 new · 1 changed · 1 unchanged · 2 can't be written"
    assert_includes response.body, "would go to config/locales/es.yml"
    picks = response.body.scan(/name="picks\[\]" value="(\d+)"/).flatten
    names = response.body.scan(/name="names\[\]" value="([^"]*)"/).flatten.map { |v| CGI.unescapeHTML(v) }
    fields = %w[locales_in values originals missings].to_h do |f|
      [f, response.body.scan(/name="#{f}\[\]" value="([^"]*)"/m).flatten.map { |v| CGI.unescapeHTML(v) }]
    end
    post "/import/apply", params: { picks: picks, names: names, locales_in: fields["locales_in"], values: fields["values"],
                                    originals: fields["originals"], missings: fields["missings"] }
    assert_includes response.body, "2 values written."
    assert_equal 'Hola, "amigo"', loaded("es.yml").dig("es", "hello")
    assert_equal "Solo en inglés", loaded("es.yml").dig("es", "only_en")
  end

  def test_import_refuses_a_value_changed_since_the_preview
    post "/import/apply", params: { picks: ["0"], names: ["hello"], locales_in: ["es"], values: ["Buenas"],
                                    originals: ["Hola de antes"], missings: ["0"] }
    assert_includes response.body, "0 values written."
    assert_includes response.body, "es.hello:"
    assert_equal "Hola", loaded("es.yml").dig("es", "hello")
  end

  def test_xliff_round_trip
    get "/export?format=xliff&target=es&q=only_en"
    xliff = response.body.sub('<target state="needs-translation"></target>', "<target>Tú &amp; yo &#x263A;</target>")
    post "/import", params: { text: xliff }
    assert_includes response.body, "1 new · 0 changed"
    assert_includes response.body, %(name="values[]" value="Tú &amp; yo ☺")
  end

  def test_import_rejects_unknown_formats
    post "/import", params: { text: "name,en\nhello,Hi\n" }
    assert_includes response.body, "The first column must be &quot;key&quot;"
  end
end
