class HomeController < ApplicationController
  def index
    @root = ENV["LOCALITO_ROOT"] || "."
    @files = Dir.glob("#{@root}/config/locales/**/*.yml").sort
  end
end
