require 'bundler'
Bundler.setup

require 'rails/version'
$VERBOSE = true

require './spec/support/silence_warnings.rb'

require 'combustion'
require 'active_record_views'

FileUtils.mkdir_p 'spec/internal/db'
File.write 'spec/internal/db/schema.rb', ''

TEST_TEMP_MODEL_DIR = Rails.root + 'spec/internal/app/models_temp'
FileUtils.mkdir_p TEST_TEMP_MODEL_DIR
Rails.application.config.paths['app/models'] << 'app/models_temp'

Combustion.initialize! :active_record, :action_controller do
  config.cache_classes = false
end
require 'rspec/rails'

RSpec.configure do |config|
  config.use_transactional_fixtures = false
  config.filter_run_when_matching focus: true
  config.filter_run_excluding skip: true
  config.example_status_persistence_file_path = 'tmp/examples.txt'

  config.mock_with :rspec do |mocks|
    mocks.verify_doubled_constant_names = true
    mocks.verify_partial_doubles = true
  end

  config.before do
    FileUtils.rm_rf Dir["spec/internal/app/models_temp/*"]

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

def with_reloader(&block)
  if Rails.application.respond_to?(:reloader)
    Rails.application.reloader.wrap(&block)
  else
    block.call
  end
end

def test_request
  with_reloader do
    status, headers, body = Rails.application.call(
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/',
      'rack.input' => StringIO.new,
    )
    expect(status).to eq 204
    body.close
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
