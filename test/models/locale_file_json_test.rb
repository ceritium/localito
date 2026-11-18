# LocaleFile's JSON handling on its own: empty files and refusals.
class LocaleFileJsonTest < Spinrail::ModelTest
  def setup
    base = ENV["TMPDIR"] || "/tmp"
    @dir = File.join(base, "localito-json-test-#{Process.pid}-#{rand(10_000)}")
    Dir.mkdir(@dir)
    @path = File.join(@dir, "en.json")
    super
  end

  def teardown
    File.delete(@path) if File.exist?(@path)
    Dir.delete(@dir)
    super
  end

  def file
    LocaleFile.new(@path)
  end

  def test_insert_into_an_empty_file_builds_the_tree
    File.write(@path, "")
    file.insert("fr.hello", "Bonjour")
    assert_equal "{\n  \"fr\": {\n    \"hello\": \"Bonjour\"\n  }\n}\n", File.read(@path)
  end

  def test_insert_finds_the_close_brace_past_strings
    File.write(@path, "{\n  \"en\": {\n    \"hello\": \"a } b\",\n    \"world\": \"x\"\n  }\n}\n")
    file.insert("en.new", "v")
    assert_equal "{\n  \"en\": {\n    \"hello\": \"a } b\",\n    \"world\": \"x\",\n    \"new\": \"v\"\n  }\n}\n", File.read(@path)
  end

  def test_update_refuses_non_scalar_members
    File.write(@path, "{\n  \"en\": {\n    \"a\": { \"x\": 1 }\n  }\n}\n")
    assert_raises(ArgumentError) { file.update("en.a.x", "2") }
  end

  def test_insert_refuses_to_go_under_a_value
    File.write(@path, "{\n  \"en\": {\n    \"a\": 1\n  }\n}\n")
    assert_raises(ArgumentError) { file.insert("en.a.b", "x") }
  end
end
