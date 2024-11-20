require 'warning'
require 'rails/version'

case Rails::VERSION::STRING
when /^6\./
  Warning.ignore(%r{lib/active_support/core_ext/class/subclasses.rb:\d+: warning: method redefined; discarding old subclasses$})
  Warning.ignore(%r{lib/action_dispatch/routing/mapper.rb:\d+: warning: URI::RFC3986_PARSER.escape is obsolete})
when /^7\.0\./
  Warning.ignore(%r{lib/active_support/core_ext/time/deprecated_conversions.rb:\d+: warning: method redefined; discarding old to_s})
  Warning.ignore(%r{lib/active_support/time_with_zone.rb:\d+: warning: previous definition of to_s was here})
  Warning.ignore(%r{lib/action_dispatch/routing/mapper.rb:\d+: warning: URI::RFC3986_PARSER.escape is obsolete})
end

Warning.process do |_warning|
  :raise
end
