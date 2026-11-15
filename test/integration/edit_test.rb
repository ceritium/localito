require_relative "../support/sample_app"

class EditTest < Spinrail::IntegrationTest
  include SampleApp

  def test_edit_keeps_the_rest_of_the_file
    before = locale_file("en.yml")
    save("posts.index.title", "en", "Articles")
    assert_response :success
    assert_equal before.sub("title: Posts # inline comment", "title: Articles"), locale_file("en.yml")
  end

  def test_edit_keeps_quoting_style
    save("hello", "es", "Hola \"tú\"")
    assert_includes locale_file("es.yml"), %(  hello: "Hola \\"tú\\"")
    save("quoted", "en", "Isn't it")
    assert_includes locale_file("en.yml"), "  quoted: 'Isn''t it'"
  end

  def test_plain_value_that_yaml_would_retype_gets_quoted
    save("posts.index.title", "es", "yes")
    assert_equal "yes", loaded("es.yml").dig("es", "posts", "index", "title")
  end

  def test_edit_block_scalar
    save("intro", "en", "One.\nTwo.\nThree.\n")
    assert_includes locale_file("en.yml"), "  intro: |\n    One.\n    Two.\n    Three.\n  folded:"
    save("folded", "es", "Una sola línea")
    assert_equal "Una sola línea", loaded("es.yml").dig("es", "folded")
  end

  def test_every_edit_round_trips
    save("greeting", "en", "Hi: %{name} # not a comment")
    data = loaded("en.yml")
    assert_equal "Hi: %{name} # not a comment", data.dig("en", "greeting")
    assert_equal "Hello", data.dig("en", "hello")
    assert_equal %w[Sunday Monday], data.dig("en", "date", "day_names")
  end

  def test_arrays_are_read_only
    get "/key?name=date.day_names"
    assert_equal "0", cell_attrs("date.day_names", "en")["editable"]
    patch "/translation", params: { name: "date.day_names", locale: "en", value: "x", original: "Sunday, Monday", inline: "1" }
    assert_response :unprocessable_entity
  end

  def test_nested_file
    save("devise.failure.locked", "en", "Locked.")
    assert_includes locale_file("devise/en.yml"), %(locked: "Locked.")
  end

  def test_value_on_the_line_after_its_key
    save("next_line", "es", "Otro")
    assert_response :success
    assert_equal "Otro", loaded("es.yml").dig("es", "next_line")
  end

  def test_edit_that_would_change_other_values_is_refused
    write_locale("es.yml", locale_file("es.yml") + "  base: &base\n    x: Uno\n  copy:\n    <<: *base\n    y: Dos\n")
    before = locale_file("es.yml")
    # copy.x comes from base.x through the merge, so editing one edits both.
    save("base.x", "es", "Otro")
    assert_response :unprocessable_entity
    assert_includes response.body, "would change other values"
    assert_equal before, locale_file("es.yml")
  end

  def test_save_over_a_value_changed_on_disk_is_refused
    get "/key?name=hello"
    original = cell_attrs("hello", "es")["original"]
    write_locale("es.yml", locale_file("es.yml").sub('"Hola"', '"Buenas"'))
    patch "/translation", params: { name: "hello", locale: "es", value: "Hey", original: original, inline: "1" }
    assert_response :conflict
    assert_includes locale_file("es.yml"), '"Buenas"'
    save("hello", "es", "Hey")
    assert_includes locale_file("es.yml"), '"Hey"'
  end

  def test_fill_a_missing_value_next_to_its_siblings
    write_locale("es.yml", locale_file("es.yml").sub("    count:\n", "    count:\n").sub("      empty: \"Aún no hay entradas\"\n", ""))
    save("posts.index.empty", "es", "Vacío")
    assert_response :success
    content = locale_file("es.yml")
    assert_includes content, "      title: Entradas\n      empty: Vacío\n    count:"
    assert_equal "Vacío", loaded("es.yml").dig("es", "posts", "index", "empty")
  end

  def test_fill_a_missing_value_creating_parents
    save("devise.failure.locked", "es", "Cuenta bloqueada")
    # devise/en.yml has it, so devise/es.yml is created for it.
    assert_equal({ "es" => { "devise" => { "failure" => { "locked" => "Cuenta bloqueada" } } } }, loaded("devise/es.yml"))
  end

  def test_fill_a_missing_value_at_the_top
    save("only_en", "es", "Solo en inglés")
    assert_equal "Solo en inglés", loaded("es.yml").dig("es", "only_en")
    assert_equal "Entradas", loaded("es.yml").dig("es", "posts", "index", "title")
  end

  def test_filling_a_value_added_meanwhile_is_refused
    get "/key?name=only_en"
    cell = cell_attrs("only_en", "es")
    write_locale("es.yml", locale_file("es.yml") + "  only_en: Ya está\n")
    patch "/translation", params: { name: "only_en", locale: "es", value: "Otro", original: "", was_missing: cell["missing"], inline: "1" }
    assert_response :conflict
    assert_equal "Ya está", loaded("es.yml").dig("es", "only_en")
  end

  def test_new_key
    post "/keys", params: { name: "posts.show.back", value_locales: %w[en es], values: ["Back", "Volver"] }
    assert_response :redirect
    assert_equal "Back", loaded("en.yml").dig("en", "posts", "show", "back")
    assert_equal "Volver", loaded("es.yml").dig("es", "posts", "show", "back")
  end

  def test_new_key_with_a_blank_locale_leaves_it_missing
    post "/keys", params: { name: "farewell", value_locales: %w[en es], values: ["Bye", ""] }
    assert_equal "Bye", loaded("en.yml").dig("en", "farewell")
    assert_nil loaded("es.yml")["es"]["farewell"]
  end

  def test_new_key_that_exists_is_refused
    post "/keys", params: { name: "hello", value_locales: %w[en], values: ["Hi"] }
    assert_response :unprocessable_entity
    assert_includes response.body, "hello already exists"
  end

  def test_new_key_under_a_value_is_refused
    post "/keys", params: { name: "hello.world", value_locales: %w[en], values: ["Hi"] }
    assert_response :unprocessable_entity
    assert_includes response.body, "hello has a value"
    assert_equal "Hello", loaded("en.yml").dig("en", "hello")
  end
end
