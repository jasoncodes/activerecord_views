require 'bundler'
Bundler.setup

require 'rails/version'
$VERBOSE = true

require 'combustion'
require 'active_record_views'
Combustion.initialize! :active_record, :action_controller do
  config.cache_classes = false
end
require 'rspec/rails'

RSpec.configure do |config|
  config.use_transactional_fixtures = false

  config.before do
    if Rails::VERSION::MAJOR >= 5
      Rails.application.reloader.reload!
    else
      ActionDispatch::Reloader.cleanup!
      ActionDispatch::Reloader.prepare!
    end

    connection = ActiveRecord::Base.connection

    connection.execute 'DROP TABLE IF EXISTS active_record_views'

    view_names = connection.select_values(<<-SQL.squish)
      SELECT table_name
      FROM information_schema.views
      WHERE table_schema = 'public';
    SQL
    view_names.each do |view_name|
      connection.execute "DROP VIEW IF EXISTS #{connection.quote_table_name view_name} CASCADE"
    end

    materialized_view_names = connection.select_values(<<-SQL.squish)
      SELECT matviewname
      FROM pg_matviews
      WHERE schemaname = 'public'
    SQL
    materialized_view_names.each do |view_name|
      connection.execute "DROP MATERIALIZED VIEW IF EXISTS #{connection.quote_table_name view_name} CASCADE"
    end
  end
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
  time = File.exist?(file) ? File.mtime(file) : Time.parse('2012-01-01')
  time = time + 1
  File.write file, new_content
  File.utime time, time, file
end

def view_names
  ActiveRecord::Base.connection.select_values(<<-SQL.squish)
    SELECT table_name
    FROM information_schema.views
    WHERE table_schema = 'public'
  SQL
end

def materialized_view_names
  ActiveRecord::Base.connection.select_values(<<-SQL.squish)
    SELECT matviewname
    FROM pg_matviews
    WHERE schemaname = 'public'
  SQL
end

def without_dependency_checks
  allow(ActiveRecordViews).to receive(:check_dependencies)
  yield
ensure
  allow(ActiveRecordViews).to receive(:check_dependencies).and_call_original
end

def without_create_enabled
  old_enabled = ActiveRecordViews::Extension.create_enabled
  ActiveRecordViews::Extension.create_enabled = false
  yield
ensure
  ActiveRecordViews::Extension.create_enabled = old_enabled
end
