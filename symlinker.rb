require 'minitest/spec'
require 'minitest/autorun'
require 'minitest/pride'
require 'fileutils'
require 'pry'

class Symlinker
  def initialize(options = {})
    @from = options[:from]
    @to   = options[:to]
    raise unless @to and @from
  end
  def link!
    FileUtils.mkdir(@to)
    Dir["#{@from}/*"].each do |entry|
      relative_path = Symlinker.path_of(entry, relative_to: @from)
      FileUtils.ln_s(entry, File.join(@to, "#{relative_path}"))
    end
  end

  private
  def self.path_of(path, options = {})
    relative_to = options[:relative_to]
    relative_to_atoms = relative_to.split("/")
    path_atoms = path.split("/")
    until path_atoms.first != relative_to_atoms.first or path_atoms.empty?
      path_atoms.shift
      relative_to_atoms.shift
    end
    path_atoms.join("/")
  end
end

describe Symlinker do
  describe '.new' do
    it "needs from and to" do
      Symlinker.new(from: "~/dotfiles", to: "~")
    end
  end
  describe '#link!' do
    before(:each) {
      FileUtils.rm_rf("sandbox")
      FileUtils.mkdir("sandbox")
      FileUtils.mkdir("sandbox/existing")
    }
    it "symlinks files" do
      FileUtils.touch("sandbox/existing/file")
      Symlinker.new(from: "sandbox/existing", to: "sandbox/new").link!
      File.symlink?("sandbox/new/file").must_equal true
    end
  end
  describe '.path_to' do
    it "works" do
      Symlinker.path_of("a/b/c", relative_to: "a/b").must_equal "c"
    end
  end

end
