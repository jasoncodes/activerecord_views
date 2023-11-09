require 'warning'
require 'rails/version'

case Rails::VERSION::STRING
when /^6\./
  Warning.ignore(%r{lib/active_support/core_ext/class/subclasses.rb:\d+: warning: method redefined; discarding old subclasses$})
when /^7\.0\./
  Warning.ignore(%r{lib/active_support/core_ext/time/deprecated_conversions.rb:\d+: warning: method redefined; discarding old to_s})
  Warning.ignore(%r{lib/active_support/time_with_zone.rb:\d+: warning: previous definition of to_s was here})
when /^7\.1\./
  raise if Gem.loaded_specs.fetch('combustion').version > Gem::Version.new('1.3.7')
  Warning.ignore(%r{ActiveRecord::Base\.clear_active_connections! is deprecated})
  Warning.ignore(%r{`Rails.application.secrets` is deprecated})
end

Warning.process do |_warning|
  :raise
end
