require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

# `localito grep` runs inside the compiled binary (app/commands/grep.rb), so
# these tests call the binary directly over a copy of test/sample_app.
class GrepTest < Minitest::Test
  SAMPLE = File.expand_path("../sample_app", __dir__)

  def setup
    @root = Dir.mktmpdir("localito-grep")
    FileUtils.cp_r("#{SAMPLE}/.", @root)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def grep(*)
    env = { "LOCALITO_ROOT" => @root, "LOCALITO_CONFIG" => "", "NO_COLOR" => "1" }
    Open3.capture2e(env, ENV.fetch("SPINRAIL_BINARY"), "grep", *)
  end

  def test_lists_every_entry_with_file_and_line
    out, status = grep
    assert status.success?, out
    assert_includes out, "config/locales/en.yml"
    assert_includes out, "config/locales/es.yml"
    assert_includes out, "config/locales/devise/en.yml"
    assert_match(/^ +\d+: en\.posts\.index\.title => Posts$/, out)
    assert_match(/^ +\d+: es\.posts\.index\.title => Entradas$/, out)
    # Array values are joined, block strings flattened onto one line.
    assert_includes out, "en.date.day_names => Sunday, Monday"
    assert_includes out, "en.intro => First line. Second line."
  end

  def test_key_filter_and_locale
    out, status = grep("-k", "posts", "-l", "es")
    assert status.success?, out
    assert_includes out, "es.posts.index.title => Entradas"
    refute_includes out, "en."
    refute_includes out, "es.hello"
  end

  def test_value_filter_ignores_case_by_default
    out, status = grep("-v", "ENTRADAS")
    assert status.success?, out
    assert_includes out, "es.posts.index.title => Entradas"
    refute_includes out, "es.hello"
  end

  def test_case_sensitive_value_filter
    out, status = grep("-s", "-v", "ENTRADAS")
    refute status.success?, out
    assert_empty out
  end

  def test_exit_code_1_without_matches
    out, status = grep("-k", "no-such-key")
    assert_equal 1, status.exitstatus
    assert_empty out
  end

  def test_changed_shows_only_entries_that_moved_since_the_base
    commit_all("en: Hello")
    write_locale("en.yml", locale_file("en.yml").sub("hello: \"Hello\"", "hello: \"Hi\""))
    out, status = grep("--changed", "--base", "HEAD")
    assert status.success?, out
    assert_includes out, "en.hello => Hi (modified)"
    refute_includes out, "en.posts.index.title"
  end

  def test_help_and_usage_errors
    out, status = grep("-h")
    assert status.success?, out
    assert_includes out, "Usage: localito grep"

    _, status = grep("--nope")
    assert_equal 2, status.exitstatus
  end

  private

  def write_locale(name, content)
    File.write(File.join(@root, "config/locales", name), content)
  end

  def locale_file(name)
    File.read(File.join(@root, "config/locales", name))
  end

  # A throwaway repository so --changed has a base to compare with.
  def commit_all(message)
    shell("git", "init", "-q")
    shell("git", "add", "-A")
    shell("git", "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-qm", message)
  end

  def shell(*cmd)
    out, status = Open3.capture2e(*cmd, chdir: @root)
    assert status.success?, "#{cmd.join(' ')} failed: #{out}"
  end
end
