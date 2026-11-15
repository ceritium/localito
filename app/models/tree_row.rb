class TreeRow
  attr_reader :path, :label, :depth, :folder, :keys, :missing

  def initialize(path, label, depth, folder, keys, missing)
    @path = path
    @label = label
    @depth = depth
    @folder = folder
    @keys = keys
    @missing = missing
  end
end
