Rake::Task['db:migrate'].enhance do
  unless ActiveRecordViews::Extension.create_enabled
    Rails.application.eager_load!
    ActiveRecordViews::Extension.process_create_queue!
    ActiveRecordViews.drop_unregistered_views!
  end
end

schema_rake_task = Gem::Version.new(Rails.version) >= Gem::Version.new("6.1") ? 'db:schema:dump' : 'db:structure:dump'

Rake::Task[schema_rake_task].enhance do
  table_exists = if Rails::VERSION::MAJOR >= 5
    ActiveRecord::Base.connection.data_source_exists?('active_record_views')
  else
    ActiveRecord::Base.connection.table_exists?('active_record_views')
  end

  if schema_rake_task == 'db:structure:dump'
    ActiveRecord::Base.schema_format = :sql
  end

  if table_exists && ActiveRecord::Base.schema_format == :sql
    tasks = ActiveRecord::Tasks::DatabaseTasks

    filename = case
    when tasks.respond_to?(:dump_filename)
      tasks.dump_filename('primary')
    else
      tasks.schema_file
    end

    config = tasks.current_config
    adapter = config.fetch('adapter')
    database = config.fetch('database')

    pg_tasks = tasks.send(:class_for_adapter, adapter).new(config)
    pg_tasks.send(:set_psql_env)

    require 'shellwords'
    system("pg_dump --data-only --table=active_record_views #{Shellwords.escape database} >> #{Shellwords.escape filename}")
    raise 'active_record_views metadata dump failed' unless $?.success?

    File.open filename, 'a' do |io|
      io.puts 'UPDATE public.active_record_views SET refreshed_at = NULL WHERE refreshed_at IS NOT NULL;'
    end
  end
end
