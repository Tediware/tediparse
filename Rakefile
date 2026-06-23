require "pathname"
require "fileutils"
abspath = Pathname.new(File.dirname(__FILE__)).expand_path
relpath = abspath.relative_path_from(Pathname.pwd)

task :default => :spec

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new do |t|
  t.verbose    = false
  t.rspec_opts = "-w -rspec_helper"

  if ENV.include?("CI")
    t.rspec_opts += " --format progress"
  else
    t.rspec_opts += " --format documentation"
  end
end

# Note options are loaded from .yardopts
require "yard"
YARD::Rake::YardocTask.new(:yard => :clobber_yard)
task :clobber_yard do
  # Call FileUtils directly rather than Rake's DSL shim: on Ruby 3.x the
  # rake-12.3 FileUtilsExt wrapper forwards its verbose/noop flags as a
  # positional argument, which the keyword-only FileUtils.rm_rf rejects.
  FileUtils.rm_rf "#{relpath}/build/generated/doc"
  FileUtils.mkdir_p "#{relpath}/build/generated/doc/images"
end

task :console do
  exec(*%w(irb -I lib -r stupidedi))
end
