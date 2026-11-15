require "fileutils"
require "tmpdir"
require "yaml"
require "cgi"

# Each test gets its own copy of test/sample_app, which the server edits.
module SampleApp
  SAMPLE = File.expand_path("../sample_app", __dir__)

  def setup
    @app_root = Dir.mktmpdir("localito-test")
    FileUtils.cp_r("#{SAMPLE}/.", @app_root)
    self.class.server_env("LOCALITO_ROOT" => @app_root, "LOCALITO_CONFIG" => config_env)
    super
  end

  def teardown
    super
    FileUtils.rm_rf(@app_root)
  end

  private

  # LOCALITO_CONFIG for the server; "" reads <root>/.localito.yml.
  def config_env
    ""
  end

  def write_config(content)
    File.write(File.join(@app_root, ".localito.yml"), content)
  end

  def locale_file(name)
    File.read(File.join(@app_root, "config/locales", name))
  end

  def write_locale(name, content)
    path = File.join(@app_root, "config/locales", name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def loaded(name)
    YAML.safe_load(locale_file(name))
  end

  # Saves as the inline editor does: with the value the page showed.
  def save(name, locale, value)
    get "/key?name=#{CGI.escape(name)}"
    cell = cell_attrs(name, locale)
    patch "/translation", params: { name: name, locale: locale, value: value, inline: "1",
                                    original: cell["original"], was_missing: cell["missing"] }
  end

  def cell_attrs(name, locale)
    tag = response.body[/<div class="cell[^"]*" data-cell="#{Regexp.escape("#{locale}.#{name}")}"[^>]*>/]
    raise "no cell #{locale}.#{name}" unless tag

    tag.scan(/data-(\w+)="([^"]*)"/).to_h { |k, v| [k, CGI.unescapeHTML(v)] }
  end

  def git(*args)
    system("git", "-C", @app_root, *args, out: File::NULL, err: File::NULL) or raise "git #{args.join(' ')} failed"
  end

  def git_init
    git("init", "-q", "-b", "main")
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "add", ".")
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "init")
  end
end
