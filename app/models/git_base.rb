# The locale values at a git ref, to compare the working tree against.
class GitBase
  @values = {}
  @runs = 0

  attr_reader :root, :ref, :sha, :error

  def initialize(root, ref, globs, excludes)
    @root = root
    @ref = ref
    @globs = globs
    @excludes = excludes
    @error = ""
    out, ok = GitBase.git(root, ["rev-parse", "--verify", "--quiet", "#{ref}^{commit}"])
    @sha = ok ? out.strip : ""
    @error = "#{ref} is not a commit here" if @sha.empty?
  end

  def self.repo?(root)
    GitBase.git(root, ["rev-parse", "--is-inside-work-tree"])[1]
  end

  def self.branches(root)
    out, ok = GitBase.git(root, ["for-each-ref", "--format=%(refname:short)", "refs/heads"])
    ok ? out.split("\n").reject(&:empty?) : []
  end

  def self.current_branch(root)
    GitBase.git(root, ["branch", "--show-current"])[0].strip
  end

  def self.head(root)
    GitBase.git(root, ["rev-parse", "--quiet", "HEAD"])[0].strip
  end

  # Through tep's shell-out: spinel's Process.wait and pipe reads crash inside
  # tep's request fibers. Output goes through a file to pass its 64 KB cap.
  def self.git(root, args)
    @runs += 1
    out_path = File.join(ENV["TMPDIR"] || "/tmp", "localito-git-#{Process.pid}-#{@runs}")
    cmd = (["git", "-C", root] + args).map { |a| GitBase.shell_quote(a) }.join(" ")
    status = Tep::Shell.run("#{cmd} > #{GitBase.shell_quote(out_path)} 2>/dev/null < /dev/null; echo $?").strip
    out = File.exist?(out_path) ? File.read(out_path) : ""
    File.delete(out_path) if File.exist?(out_path)
    [out, status == "0"]
  end

  def self.shell_quote(arg)
    "'#{arg.gsub("'") { "'\\''" }}'"
  end

  def available?
    !@sha.empty?
  end

  # "es.posts.title" => value, read once per commit and glob set.
  def values
    return {} unless available?

    cache_key = "#{@root}|#{@sha}|#{@globs.join(',')}|#{@excludes.join(',')}"
    cached = GitBase.cached(cache_key)
    return cached if cached

    out = {}
    paths.each do |path|
      content, ok = GitBase.git(@root, ["show", "#{@sha}:./#{path}"])
      next unless ok

      begin
        LocaleFile.values(content).each { |k, v| out[k] = v unless out.key?(k) }
      rescue StandardError
        next
      end
    end
    GitBase.store(cache_key, out)
    out
  end

  def self.cached(key)
    @values[key]
  end

  def self.store(key, values)
    @values = {} if @values.size > 20
    @values[key] = values
  end

  private

  def paths
    out, ok = GitBase.git(@root, ["ls-tree", "-r", "--name-only", @sha])
    return [] unless ok

    patterns = @globs.map { |glob| GitBase.glob_regexp(glob) }
    excluded = @excludes.map { |glob| GitBase.glob_regexp(glob) }
    out.split("\n").select do |path|
      patterns.any? { |re| re.match?(path) } && excluded.none? { |re| re.match?(path) }
    end.sort
  end

  # "config/locales/**/*.yml" as a Regexp over repo-relative paths.
  def self.glob_regexp(glob)
    out = +"\\A"
    i = 0
    while i < glob.length
      c = glob[i]
      if glob[i, 3] == "**/"
        out << "(?:.*/)?"
        i += 3
        next
      elsif glob[i, 2] == "**"
        out << ".*"
        i += 2
        next
      elsif c == "*"
        out << "[^/]*"
      elsif c == "?"
        out << "[^/]"
      else
        out << Regexp.escape(c)
      end
      i += 1
    end
    Regexp.new("#{out}\\z")
  end
end
