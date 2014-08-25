#TODO: integrate into Rakefile
require 'fileutils'
require 'erb'

class Symlinker
  def initialize(options = {})
    @from = options[:from]
    @to   = options[:to]
    @ui   = options[:ui] || SymlinkerUI.new
    raise unless @to and @from
  end
  def link!
    FileUtils.mkdir(@to) unless File.directory?(@to)
    Dir["#{@from}/*"].each do |entry|
      relative_path = Symlinker.path_of(entry, relative_to: @from)
      target = File.absolute_path(File.join(@to, "#{relative_path}"))
      source = File.absolute_path(entry)
      if source =~ /\.erb$/
        generate_file(source, target)
      else
        link_helper(source, target)
      end
    end
  end

  private
  def link_helper(source,target)
    identical = false
    if file_already_there?(target)
      if File.identical?(source,target)
        @ui.identical(target)
        identical = true
      else
        response = @ui.file_exists(target)
      end
    end
    if not file_already_there?(target)
      FileUtils.ln_s(source, target)
      @ui.linked(source, target)
    elsif file_already_there?(target) and response == :overwrite
      FileUtils.ln_sf(source, target)
      @ui.overwritten(source, target)
    elsif file_already_there?(target) and not identical
      @ui.skipped(target)
    end
  end
  def generate_file(source, target)
    target_without_erb = target.gsub(/\.erb$/,'')
    File.open(target_without_erb, 'w') do |new_file|
      content = ERB.new(File.read(source)).result(binding)
      new_file.write content
    end
  end
  def file_already_there?(path)
    File.exists?(path) or File.symlink?(path)
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
  def file_exists(path)
    decision = nil
    until decision
      @out.print "Overwrite #{relative_path(path)}? [y/n] "
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
