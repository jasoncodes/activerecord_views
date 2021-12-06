require 'warning'
require 'rails/version'

Warning.process do |_warning|
  :raise
end
