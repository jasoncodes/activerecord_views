require 'bundler'
Bundler.setup

require 'combustion'
require 'active_record_views'
Combustion.initialize! :active_record, :action_controller do
  config.cache_classes = false
end
require 'rspec/rails'

RSpec.configure do |config|
  config.use_transactional_fixtures = true
end

def test_request
  begin
    Rails.application.call({'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/'})
  rescue ActionController::RoutingError
  end
end

def with_temp_sql_dir
  Dir.mktmpdir do |temp_dir|
    begin
      old_sql_load_path = ActiveRecordViews.sql_load_path
      ActiveRecordViews.sql_load_path = [temp_dir] + old_sql_load_path
      yield temp_dir
    ensure
      ActiveRecordViews.sql_load_path = old_sql_load_path
    end
  end
end

def update_file(file, new_content)
  time = File.exists?(file) ? File.mtime(file) : Time.parse('2012-01-01')
  time = time + 1
  File.write file, new_content
  File.utime time, time, file
end
