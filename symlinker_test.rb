require_relative 'symlinker'
require 'minitest/spec'
require 'minitest/autorun'
require 'minitest/pride'
require 'stringio'
require 'pathname'

describe Symlinker do
  def create_file(path, content = "Created by create_file", options = {})
    absolute_path = File.absolute_path(path)
    File.open(absolute_path, "w+") {|file| file.write content}
    if options[:mtime]
      FileUtils.touch(absolute_path, mtime: options[:mtime])
    end
  end
  def create_dir(path)
    FileUtils.mkdir_p(path)
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
      ui.expect :linked, nil, [File.absolute_path("sandbox/existing/file"), File.absolute_path("sandbox/new/file")]
      create_file "sandbox/existing/file"
      symlinker.link!
      ui.verify
      IO.read("sandbox/new/file").must_equal "Created by create_file"
    end
    it "symlinks directories" do
      ui.expect :linked, nil, [File.absolute_path("sandbox/existing/dir"), File.absolute_path("sandbox/new/dir")]
      create_dir "sandbox/existing/dir"
      symlinker.link!
      ui.verify
      File.symlink?("sandbox/new/dir").must_equal true
    end
    it "symlinks nested directories" do
      ui.expect :linked, nil, [File.absolute_path("sandbox/existing/dir"), File.absolute_path("sandbox/new/dir")]
      create_dir  "sandbox/existing/dir"
      create_file "sandbox/existing/dir/file"
      symlinker.link!
      ui.verify
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
          ui.expect :file_exists, :dont_overwrite, [File.absolute_path("sandbox/new/file")]
          ui.expect :skipped, :nil, [File.absolute_path("sandbox/new/file")]
          symlinker.link!
          ui.verify
        end
        it 'does not touch the file if user says to not overwrite' do
          ui.expect :file_exists, :dont_overwrite, [File.absolute_path("sandbox/new/file")]
          ui.expect :skipped, :nil, [File.absolute_path("sandbox/new/file")]
          symlinker.link!
          ui.verify
          IO.read("sandbox/new/file").must_equal "I was here first"
        end
        it 'changes file if user says to overwrite' do
          ui.expect :file_exists, :overwrite, [File.absolute_path("sandbox/new/file")]
          ui.expect :overwritten, :nil, [File.absolute_path("sandbox/existing/file"),File.absolute_path("sandbox/new/file")]
          symlinker.link!
          ui.verify
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
          IO.read("sandbox/new/file").must_equal "File to be linked"
        end
      end
    end
    describe 'with erb files' do
      describe 'when the file does not exist' do
        it 'expands the file first' do
          ui.expect :generated, nil, [File.absolute_path("sandbox/existing/file.erb"),File.absolute_path("sandbox/new/file")]
          ENV['variable'] = "World"
          create_file "sandbox/existing/file.erb", "Hello, <%= ENV['variable'] %>!"
          symlinker.link!
          ui.verify
          IO.read("sandbox/new/file").must_equal "Hello, World!"
        end
      end
      describe 'when the file exists but is identical' do
        before(:each) do
          create_dir "sandbox/new"
          create_file "sandbox/new/file", "Hello, World!", mtime: Time.now - 3660
        end
        it 'expands the file first' do
          ui.expect :identical, nil, [File.absolute_path("sandbox/existing/file.erb"),File.absolute_path("sandbox/new/file")]
          ENV['variable'] = "World"
          create_file "sandbox/existing/file.erb", "Hello, <%= ENV['variable'] %>!"
          symlinker.link!
          ui.verify
          IO.read("sandbox/new/file").must_equal "Hello, World!"
          File.mtime("sandbox/new/file").must_be_close_to Time.now - 3600, 100
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

describe SymlinkerUI do
  let(:ui) { SymlinkerUI.new(out: output_stream, in: input_stream) }
  let(:output_stream) { StringIO.new }
  let(:input_stream) { MiniTest::Mock.new }
  describe '#linked' do
    it 'prints the right message' do
      ui.linked(File.absolute_path("sandbox/existing/file"),File.absolute_path("sandbox/new/file"))
      output_stream.string.must_equal "sandbox/new/file: Linked to sandbox/existing/file\n"
    end
  end
  describe '#overwritten' do
    it 'prints the right message' do
      ui.overwritten(File.absolute_path("sandbox/existing/file"),File.absolute_path("sandbox/new/file"))
      output_stream.string.must_equal "sandbox/new/file: Linked to sandbox/existing/file [Overwritten]\n"
    end
  end
  describe '#skipped' do
    it 'prints the right message' do
      ui.skipped(File.absolute_path("sandbox/new/file"))
      output_stream.string.must_equal "sandbox/new/file: Skipped\n"
    end
  end
  describe '#identical' do
    it 'prints the right message' do
      ui.identical(File.absolute_path("sandbox/new/file"))
      output_stream.string.must_equal "sandbox/new/file: Identical\n"
    end
  end
  describe '#generated' do
    it 'prints the right message' do
      ui.generated(File.absolute_path("sandbox/existing/file.erb"),File.absolute_path("sandbox/new/file"))
      output_stream.string.must_equal "sandbox/new/file: Generated from sandbox/existing/file.erb\n"
    end
  end
  describe '#file_exists' do
    it 'prints the right thing' do
      input_stream.expect :gets, "y\n"
      ui.file_exists(File.absolute_path("sandbox/new/file"))
      output_stream.string.must_equal "Overwrite sandbox/new/file? [y/n] "
    end
    it 'returns :overwrite when user answers with "y"' do
      input_stream.expect :gets, "y\n"
      ui.file_exists(File.absolute_path("sandbox/new/file")).must_equal :overwrite
      input_stream.verify
    end
    it 'returns :dont_overwrite when user answers with "n"' do
      input_stream.expect :gets, "n\n"
      ui.file_exists(File.absolute_path("sandbox/new/file")).must_equal :dont_overwrite
      input_stream.verify
    end
    it 'asks again when the answer did not compute' do
      input_stream.expect :gets, "Something\n"
      input_stream.expect :gets, "y\n"
      ui.file_exists(File.absolute_path("sandbox/new/file")).must_equal :overwrite
      output_stream.string.must_equal "Overwrite sandbox/new/file? [y/n] Overwrite sandbox/new/file? [y/n] "
    end
  end
end
