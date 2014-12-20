# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'active_record_views/version'

Gem::Specification.new do |gem|
  gem.name = 'activerecord_views'
  gem.version = ActiveRecordViews::VERSION
  gem.authors = ['Jason Weathered']
  gem.email = ['jason@jasoncodes.com']
  gem.summary = %q{Automatic database view creation for ActiveRecord}
  gem.homepage = 'http://github.com/jasoncodes/activerecord_views'
  gem.license = 'MIT'

  gem.files = `git ls-files`.split($/)
  gem.executables = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']

  gem.add_dependency 'activerecord', ['>= 3.2', '< 4.3']

  gem.add_development_dependency 'appraisal'
  gem.add_development_dependency 'rspec-rails', '>= 2.14'
  gem.add_development_dependency 'combustion', '>= 0.5.1'
  gem.add_development_dependency 'pg'
end
