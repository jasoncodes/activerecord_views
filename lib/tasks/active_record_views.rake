Rake::Task['db:migrate'].enhance do
  if Rails.application.config.cache_classes
    Rails.application.eager_load!
    ActiveRecordViews::Extension.process_create_queue!
    ActiveRecordViews.drop_unregistered_views!
  end
end

Rake::Task['db:structure:dump'].enhance do
  table_exists = if Rails::VERSION::MAJOR >= 5
    ActiveRecord::Base.connection.data_source_exists?('active_record_views')
  else
    ActiveRecord::Base.connection.table_exists?('active_record_views')
  end

  if table_exists
    filename = ENV['DB_STRUCTURE'] || File.join(Rails.root, "db", "structure.sql")

    if defined? ActiveRecord::Tasks::DatabaseTasks
      tasks = ActiveRecord::Tasks::DatabaseTasks
      config = tasks.current_config
      tasks.send(:class_for_adapter, config.fetch('adapter')).new(config)
      pg_tasks = tasks.send(:class_for_adapter, config.fetch('adapter')).new(config)
      pg_tasks.send(:set_psql_env)
    else
      config = current_config
      set_psql_env(config)
    end

    require 'shellwords'
    system("pg_dump --data-only --table=active_record_views #{Shellwords.escape config['database']} >> #{Shellwords.escape filename}")
    raise 'active_record_views metadata dump failed' unless $?.success?

    File.open filename, 'a' do |io|
      io.puts 'UPDATE public.active_record_views SET refreshed_at = NULL WHERE refreshed_at IS NOT NULL;'
    end
  end
end
