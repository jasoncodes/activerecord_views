require 'warning'
require 'rails/version'

case Rails::VERSION::STRING
when /^4\.2\./
  Warning.ignore(%r{lib/(active_support/core_ext|action_dispatch/middleware)/.+: warning: (method redefined|previous definition)})
  Warning.ignore(%r{lib/active_support/core_ext/.+: warning: BigDecimal.new is deprecated})
  Warning.ignore(%r{lib/arel/visitors/informix.rb:\d+: warning: assigned but unused variable})
  Warning.ignore(%r{lib/active_record/connection_adapters/.+: warning: deprecated Object#=~ is called on Integer})
  Warning.ignore(%r{Inheriting from Rack::Session::Abstract::ID is deprecated})
when /^5\.0\./
  Warning.ignore(%r{lib/(active_support/core_ext|action_view)/.+: warning: (method redefined|previous definition)})
  Warning.ignore(%r{lib/arel/visitors/informix.rb:\d+: warning: assigned but unused variable})
  Warning.ignore(%r{lib/action_view/.+: warning: `\*' interpreted as argument prefix})
when /^5\.1\./
  Warning.ignore(%r{lib/(active_support/core_ext)/.+: warning: (method redefined|previous definition)})
  Warning.ignore(%r{lib/arel/visitors/informix.rb:\d+: warning: assigned but unused variable})
  Warning.ignore(%r{lib/active_record/.+/schema_statements.rb:\d+: (warning: in `drop_table': the last argument was passed as a single Hash|warning: although a splat keyword arguments here)})
end

Warning.process do |_warning|
  :raise
end
