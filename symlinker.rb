require 'minitest/spec'
require 'minitest/autorun'
require 'minitest/pride'
require 'fileutils'
require 'pry'

class Symlinker
  def initialize(options = {})
    @from = options[:from]
    @to   = options[:to]
    @ui   = options[:ui]
    raise unless @to and @from
  end
  def link!
    FileUtils.mkdir(@to) unless File.directory?(@to)
    Dir["#{@from}/*"].each do |entry|
      relative_path = Symlinker.path_of(entry, relative_to: @from)
      target = File.absolute_path(File.join(@to, "#{relative_path}"))
      source = File.absolute_path(entry)
      link_helper(source, target)
    end
  end

  private
  def link_helper(source,target)
    if File.exists?(target) or File.symlink?(target)
      if File.identical?(source,target)
        @ui.identical(target)
      else
        response = @ui.file_exists(target)
      end
    end
    if not File.exists?(target) and not File.symlink?(target)
      FileUtils.ln_s(source, target)
    elsif File.exists?(target) and response == :override
      FileUtils.ln_sf(source, target)
    end
  end
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
  def create_file(full_path, content = "Created by create_file")
    File.open(full_path, "w+") {|file| file.write content}
  end
  def create_dir(full_path)
    FileUtils.mkdir_p(full_path)
  end
  def link_file(source, target)
    FileUtils.ln_s(File.absolute_path(source), File.absolute_path(target))
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
      Symlinker.new(from: "sandbox/existing", to: "sandbox/new", ui: ui)
    end
    let(:ui) do
      MiniTest::Mock.new
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
    describe 'when the file already exists' do
      before(:each) do
        create_dir  "sandbox/new"
          create_file "sandbox/existing/file", "File to be linked"
      end
      describe 'and they are different' do
        before(:each) do
          create_file "sandbox/new/file", "I was here first"
        end
        it 'asks the user how to proceed' do
          ui.expect :file_exists, :dont_override, [File.absolute_path("sandbox/new/file")]
          symlinker.link!
          ui.verify
        end
        it 'does not touch the file if user says to not override' do
          ui.expect :file_exists, :dont_override, [File.absolute_path("sandbox/new/file")]
          symlinker.link!
          IO.read("sandbox/new/file").must_equal "I was here first"
        end
        it 'changes file if user says to override' do
          ui.expect :file_exists, :override, [File.absolute_path("sandbox/new/file")]
          symlinker.link!
          IO.read("sandbox/new/file").must_equal "File to be linked"
        end
      end
      describe 'and they are identical' do
        before(:each) do
          link_file "sandbox/existing/file", "sandbox/new/file"
        end
        it 'does not ask the user' do
          ui.expect :identical, nil, [File.absolute_path("sandbox/new/file")]
          symlinker.link!
          ui.verify
        end
      end
    end
  end

  describe '.path_to' do
    it "works" do
      Symlinker.path_of("a/b/c", relative_to: "a/b").must_equal "c"
    end
  end

end
