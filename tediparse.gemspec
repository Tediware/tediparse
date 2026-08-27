require File.dirname(__FILE__) + "/lib/stupidedi/version"

Gem::Specification.new do |s|
  s.name        = "tediparse"
  s.summary     = "Parse, generate, validate ASC X12 EDI"
  s.description = "A fork of stupidedi by Kyle Putnam. A parser and generator for X12 EDI documents. X12 content is not included — users must supply their own licensed X12 data."
  s.homepage    = "https://github.com/Tediware/tediparse"

  s.version = Stupidedi::VERSION
  s.authors = ["Kyle Putnam", "Isi Robayna", "Adrian Duyzer"]

  # Set explicitly, though "ruby" is already the default. RubyGems 3.6.1
  # serializes an unset platform as `original_platform: ''`, which
  # rubygems.org rejects at push time with "Platform can't be blank".
  # Assigning it makes the attribute serialize correctly on any version.
  s.platform = Gem::Platform::RUBY

  s.email   = "adrian@tediware.com"
  s.license = "BSD-3-Clause"

  s.metadata = {
    "source_code_uri" => s.homepage,
    "changelog_uri"   => "#{s.homepage}/blob/master/CHANGELOG.md",
    "bug_tracker_uri" => "#{s.homepage}/issues",
  }

  s.required_ruby_version = ">= 2.6"

  s.files             = ["README.md", "CHANGELOG.md", "LICENSE", "Rakefile",
                         "lib/**/*",
                         "bin/**/*",
                         "doc/**/*.md"].map {|glob| Dir[glob] }.flatten
  s.require_path      = "lib"
  s.bindir            = "bin"
  s.executables       = ["tediparse"]

  s.add_dependency "term-ansicolor", "~> 1.3"
  s.add_dependency "cantor",         "~> 1.2.1"
  # s.metadata["yard.run"] = "yard doc"
end
