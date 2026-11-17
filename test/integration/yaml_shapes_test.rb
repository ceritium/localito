require_relative "../support/sample_app"

# Shapes found in real locale files, beyond plain nested scalars.
class YamlShapesTest < Spinrail::IntegrationTest
  include SampleApp

  def test_merge_keys
    write_locale("fr.yml", "fr:\n  base: &base\n    one: Un\n  copy:\n    <<: *base\n    two: Deux\n")
    get "/"
    assert_includes response.body, "copy.one"
    assert_includes response.body, "Deux"
    assert_no_file_error
  end

  def test_symbols_and_dates
    write_locale("fr.yml", "fr:\n  date:\n    order:\n      - :day\n      - :month\n    released: 2024-01-31\n  sym: :short\n  title: Titre\n")
    get "/"
    assert_includes response.body, "Titre"
    assert_includes response.body, "day, month"
    assert_includes response.body, "2024-01-31"
    assert_no_file_error
  end

  def test_editing_a_date_keeps_it_text
    write_locale("fr.yml", "fr:\n  released: 2024-01-31\n  other: 2023-05-01\n")
    save("released", "fr", "2025-02-01")
    assert_response :success
    assert_includes locale_file("fr.yml"), "released: \"2025-02-01\""
    assert_includes locale_file("fr.yml"), "other: 2023-05-01"
  end

  def test_ruby_object_tags
    write_locale("fr.yml", "fr:\n  one: Un\n  two: !ruby/object:OpenStruct\n    table:\n      x: X\n  three: Trois\n")
    get "/"
    assert_includes response.body, "Trois"
    assert_includes response.body, "[object: OpenStruct]"
    refute_includes response.body, "two.table.x"
    assert_equal "0", cell_attrs("two", "fr")["editable"]
    assert_no_file_error
    save("three", "fr", "3")
    assert_response :success
    assert_includes locale_file("fr.yml"), "two: !ruby/object:OpenStruct"
  end

  def test_block_text_that_looks_like_a_date_is_kept
    write_locale("fr.yml", "fr:\n  notes: |\n    since: 2024-01-31\n    done\n  after: Après\n")
    get "/"
    assert_includes response.body, "since: 2024-01-31\ndone"
    save("after", "fr", "Ensuite")
    assert_response :success
  end

  def test_document_marker_and_comments
    write_locale("fr.yml", "---\n# top\nfr:\n  # inside\n  one: Un # trailing\n")
    get "/"
    assert_includes response.body, "Un"
    save("one", "fr", "Une")
    assert_response :success
    assert_includes locale_file("fr.yml"), "# top"
  end

  def test_folded_and_wrapped_values
    write_locale("fr.yml", "fr:\n  folded: >\n    Un\n    paragraphe\n  wrapped: \"Une ligne\n    coupée\"\n  after: Après\n")
    get "/"
    assert_includes response.body, "Un paragraphe"
    assert_includes response.body, "Une ligne coupée"
    save("after", "fr", "Ensuite")
    assert_response :success
    assert_equal "Une ligne coupée", loaded("fr.yml").dig("fr", "wrapped")
  end

  def test_invalid_file_is_reported_and_others_still_load
    write_locale("fr.yml", "fr:\n  one: [unclosed\n")
    get "/"
    assert_includes response.body, "config/locales/fr.yml:"
    assert_includes response.body, "Entradas"
  end

  def test_crlf_files_are_editable_and_keep_crlf
    write_locale("fr.yml", "fr:\r\n  one: Un\r\n  nested:\r\n    two: Deux\r\n")
    save("nested.two", "fr", "Zwei")
    assert_response :success
    save("hello", "fr", "Bonjour")
    assert_response :success
    assert_equal "fr:\r\n  one: Un\r\n  nested:\r\n    two: Zwei\r\n  hello: Bonjour\r\n", locale_file("fr.yml")
  end

  def test_files_with_a_bom_are_editable_and_keep_it
    write_locale("fr.yml", "\uFEFFfr:\n  one: Un\n")
    save("one", "fr", "Une")
    assert_response :success
    assert_equal "\uFEFFfr:\n  one: Une\n", locale_file("fr.yml")
  end

  def test_an_anchored_value_keeps_its_anchor
    write_locale("fr.yml", "fr:\n  one: &one Un\n  two: Deux\n")
    save("one", "fr", "Une")
    assert_response :success
    assert_includes locale_file("fr.yml"), "one: &one Une"
  end

  def test_an_aliased_value_is_refused
    write_locale("fr.yml", "fr:\n  one: &one Un\n  copy: *one\n")
    save("one", "fr", "Une")
    assert_response :unprocessable_entity
    assert_includes locale_file("fr.yml"), "one: &one Un\n"
  end

  def test_multiline_flow_mappings_are_read_only
    write_locale("fr.yml", "fr:\n  meta: {\n    a: 1,\n    b: 2\n  }\n")
    get "/key?name=meta.a"
    assert_equal "0", cell_attrs("meta.a", "fr")["editable"]
  end

  private

  def assert_no_file_error
    refute_includes response.body, "config/locales/fr.yml:"
  end
end
