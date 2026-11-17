require "minitest/autorun"
require "open3"

# bin/localito dispatches subcommands before touching the server, so the
# usage paths need neither a build nor a free port.
class CliTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  BIN = File.join(ROOT, "bin/localito")

  def localito(*)
    Open3.capture2e(BIN, *, chdir: ROOT)
  end

  def test_prints_the_usage_without_a_command
    out, status = localito
    assert_equal 2, status.exitstatus
    assert_includes out, "localito web [DIR] [options]"
  end

  def test_help_exits_zero_before_and_after_the_subcommand
    %w[-h --help].each do |flag|
      out, status = localito(flag)
      assert status.success?, out
      assert_includes out, "localito web [DIR] [options]"
    end
    _, status = localito("web", "--help")
    assert status.success?
  end

  def test_unknown_command_and_option_exit_two
    out, status = localito("wbe")
    assert_equal 2, status.exitstatus
    assert_includes out, "unknown command: wbe"

    _, status = localito("--nope")
    assert_equal 2, status.exitstatus
  end
end
