require_relative "../support/sample_app"

# .json locale files: read through the same loader as YAML, edited by
# replacing only the value token (commas, order and formatting kept), missing
# keys inserted in the right object. https://github.com/ceritium/localito/issues/1
class JsonTest < Spinrail::IntegrationTest
  include SampleApp

  EN_JSON = <<~JSON
    {
      "en": {
        "hello": "Hello",
        "posts": {
          "index": {
            "title": "Posts",
            "empty": "No posts"
          }
        },
        "meta": { "a": 1, "b": true },
        "count": 2
      }
    }
  JSON

  def json_setup
    write_config(<<~YAML)
      paths:
        - "config/locales/**/*.json"
    YAML
    write_locale("en.json", EN_JSON)
  end

  # A key no locale has yet has no /key page; add it the way the new-key
  # form does (was_missing drives Translations#add).
  def save_missing(name, locale, value)
    patch "/translation", params: { name: name, locale: locale, value: value, inline: "1",
                                    original: "", was_missing: "1" }
  end

  def test_json_files_read_values
    json_setup
    get "/"
    assert_includes response.body, "Hello"
    assert_includes response.body, "Posts"
    get "/key?name=hello"
    assert_equal "1", cell_attrs("hello", "en")["editable"]
  end

  def test_json_edit_replaces_only_the_value
    json_setup
    save("hello", "en", "Hi there")
    assert_response :success
    assert_equal EN_JSON.sub('"hello": "Hello"', '"hello": "Hi there"'), locale_file("en.json")
    save("count", "en", "3")
    assert_response :success
    assert_includes locale_file("en.json"), '"count": "3"'
  end

  def test_json_edit_escapes_the_value
    json_setup
    save("hello", "en", %(He said "hi"\nnext))
    assert_response :success
    assert_includes locale_file("en.json"), %("hello": "He said \\"hi\\"\\nnext",)
    assert_equal %(He said "hi"\nnext), loaded("en.json")["en"]["hello"]
  end

  def test_json_insert_inside_an_object
    json_setup
    save_missing("posts.new_key", "en", "value")
    assert_response :success
    assert_equal EN_JSON.sub(%(        "empty": "No posts"\n      }),
                             %(        "empty": "No posts"\n      },\n      "new_key": "value")),
                 locale_file("en.json")
  end

  def test_json_insert_inside_an_inline_object
    json_setup
    save_missing("meta.c", "en", "x")
    assert_response :success
    assert_includes locale_file("en.json"), '"meta": { "a": 1, "b": true, "c": "x" },'
  end

  def test_json_missing_key_goes_to_the_locale_mirror
    json_setup
    put_file("config/locales/fr.json", "{\n  \"fr\": {\n    \"keep\": \"x\"\n  }\n}\n")
    save("hello", "fr", "Bonjour")
    assert_response :success
    assert_equal "{\n  \"fr\": {\n    \"keep\": \"x\",\n    \"hello\": \"Bonjour\"\n  }\n}\n", locale_file("fr.json")
  end

  def test_json_files_group_across_locales
    write_config(<<~YAML)
      paths:
        - "config/locales/**/*.json"
    YAML
    write_locale("messages.en.json", "{\n  \"en\": { \"hello\": \"Hello\" }\n}\n")
    write_locale("messages.es.json", "{\n  \"es\": { \"hello\": \"Hola\" }\n}\n")
    get "/"
    assert_includes response.body, %(title="config/locales/messages.*.json")
  end

  def test_json_complex_values_are_read_only
    json_setup
    put_file("config/locales/complex.json", "{\n  \"en\": {\n    \"list\": [1, 2],\n    \"obj\": { \"x\": 1 }\n  }\n}\n")
    get "/key?name=list"
    assert_equal "0", cell_attrs("list", "en")["editable"]
    get "/key?name=obj.x"
    assert_equal "0", cell_attrs("obj.x", "en")["editable"]
  end

  def test_yaml_files_are_discovered_without_config
    write_locale("en.yaml", "en:\n  hello: Hi\n")
    get "/"
    assert_includes response.body, "Hi"
  end
end
