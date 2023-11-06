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
  config.active_support.deprecation = -> (message, _callstack, _deprecator) do
    warn message
  end
  config.cache_classes = false
  config.secret_key_base = 'dummy'
  if Gem::Version.new(Rails.version) >= Gem::Version.new("6.1")
    config.active_record.legacy_connection_handling = false
  end
end
require 'rspec/rails'

RSpec.shared_context 'sql_statements' do
  let(:sql_statements) { [] }

  let!(:sql_statements_subscription) do
    ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, details|
      sql_statements << details.fetch(:sql)
    end
  end

  after do
    ActiveSupport::Notifications.unsubscribe sql_statements_subscription
  end
end

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

    Rails.application.reloader.reload!

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

  config.include_context 'sql_statements'
end

def test_request
  status, headers, body = Rails.application.call(
    'REQUEST_METHOD' => 'GET',
    'PATH_INFO' => '/',
    'rack.input' => StringIO.new,
  )
  expect(status).to eq 204
  body.close
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
