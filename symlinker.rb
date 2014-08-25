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
      target = File.absolute_path(File.join(@to, "#{relative_path}"))
      source = File.absolute_path(entry)
      FileUtils.ln_s(source, target)
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
  def create_file(full_path)
    File.open(full_path, "w+") {|file| file.write "Created by create_file"}
  end
  def create_dir(full_path)
    FileUtils.mkdir_p(full_path)
  end

  describe '.new' do
    it "needs from and to" do
      Symlinker.new(from: "~/dotfiles", to: "~")
      proc { Symlinker.new(from: "~/dotfiles") }.must_raise RuntimeError
    end
  end

  describe '#link!' do
    before(:each) {
      FileUtils.rm_rf("sandbox")
      FileUtils.mkdir("sandbox")
      FileUtils.mkdir("sandbox/existing")
    }
    let(:symlinker) do
      Symlinker.new(from: "sandbox/existing", to: "sandbox/new")
    end
    it "symlinks files" do
      create_file "sandbox/existing/file"
      symlinker.link!
      IO.read("sandbox/new/file").must_equal "Created by create_file"
    end
    it "symlinks directories" do
      create_dir "sandbox/existing/dir"
      symlinker.link!
      File.symlink?("sandbox/new/dir").must_equal true
    end
    it "symlinks nested directories" do
      create_dir  "sandbox/existing/dir"
      create_file "sandbox/existing/dir/file"
      symlinker.link!
      IO.read("sandbox/new/dir/file").must_equal "Created by create_file"
    end
  end

  describe '.path_to' do
    it "works" do
      Symlinker.path_of("a/b/c", relative_to: "a/b").must_equal "c"
    end
  end

end
