#TODO: integrate into Rakefile
require 'fileutils'
require 'erb'
require 'tempfile'
require 'pathname'

class Symlinker
  def initialize(options = {})
    @from    = options[:from]
    @to      = options[:to]
    @ui      = options[:ui] || SymlinkerUI.new
    @ignored = []
    raise unless @to and @from
  end

  def ignore(*files)
    @ignored += files
    self
  end

  def link!
    FileUtils.mkdir(@to) unless File.directory?(@to)
    entries_to_link.each do |entry|
      relative_path = Symlinker.path_of(entry, relative_to: @from)
      target = File.absolute_path(File.join(@to, "#{relative_path}"))
      source = File.absolute_path(entry)
      if source =~ /\.erb$/
        target = target.gsub(/\.erb$/,'')
        generate_file(source, target)
      else
        link_helper(source, target)
      end
    end
  end

  private
  def entries_to_link
    entries = Dir["#{@from}/*"]
    # unless @ignored.empty?
    #   p "<>"
    #   p @ignored
    #   p entries
    #   p a
    #   p "</>"
    # end
    entries.reject do |entry|
      relative_path = remove_beginning(@from, entry)
      without_leading_slash = remove_beginning("/", relative_path)
      @ignored.include? relative_path or
        @ignored.include? without_leading_slash
    end
  end

  def remove_beginning(beginning, full_string)
    if full_string.start_with? beginning
      full_string[beginning.length, full_string.length - beginning.length]
    else
      full_string
    end
  end

  def link_helper(source,target)
    if file_already_there?(target) and File.identical?(source,target)
      @ui.identical(target)
      identical = true
    elsif file_already_there?(target)
      if @ui.file_exists(target) == :overwrite
        FileUtils.ln_sf(source, target)
        @ui.overwritten(source, target)
      else
        @ui.skipped(target)
      end
    else
      FileUtils.ln_s(source, target)
      @ui.linked(source, target)
    end
  end

  def generate_file(source, target)
    content = ERB.new(File.read(source)).result(binding)
    write_file = lambda do
      File.open(target, 'w') do |new_file|
        new_file.write content
      end
    end
    if file_already_there?(target) and same_content?(content, target)
      @ui.identical(source, target)
    elsif file_already_there?(target)
      if @ui.erb_files_differ(target,IO.read(target),content) == :overwrite
        write_file.call
        @ui.overwritten(source, target)
      else
        @ui.skipped(target)
      end
    else
      write_file.call
      @ui.generated(source, target)
    end
  end

  def file_already_there?(path)
    File.exists?(path) or File.symlink?(path)
  end

  def same_content?(content, file)
    IO.read(file) == content
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

class SymlinkerUI
  def initialize(options = {})
    @out = options[:out] || STDOUT
    @in = options[:in] || STDIN
  end
  def linked(source, target)
    @out.puts "#{relative_path(target)}: Linked to #{relative_path(source)}"
  end
  def overwritten(source, target)
    @out.puts "#{relative_path(target)}: Linked to #{relative_path(source)} [Overwritten]"
  end
  def skipped(path)
    @out.puts "#{relative_path(path)}: Skipped"
  end
  def identical(path)
    @out.puts "#{relative_path(path)}: Identical"
  end
  def generated(source, target)
    @out.puts "#{relative_path(target)}: Generated from #{relative_path(source)}"
  end
  def erb_files_differ(path,existing_content,new_content)
    diff = "Existing content:\n#{existing_content}"
    diff += "\n---\n"
    diff += "New content:\n#{new_content}"
    file_exists(path, diff)
  end
  def file_exists(path, diff = nil)
    decision = nil
    until decision
      @out.print "Overwrite #{relative_path(path)}? [y/n] "
      @out.print diff if diff
      decision = case @in.gets.chomp
      when 'y'
        :overwrite
      when 'n'
        :dont_overwrite
      else
        nil
      end
    end
    decision
  end

  private
  def relative_path(path)
    pwd = Pathname.new(Dir.pwd)
    Pathname.new(path).relative_path_from(pwd).to_s
  end
end
