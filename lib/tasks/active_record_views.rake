Rake::Task['db:structure:dump'].enhance do
  if ActiveRecord::Base.connection.table_exists?('active_record_views')
    filename = ENV['DB_STRUCTURE'] || File.join(Rails.root, "db", "structure.sql")
    config = current_config
    set_psql_env(config)
    system("pg_dump --data-only --table=active_record_views #{Shellwords.escape config['database']} >> #{Shellwords.escape filename}")
    raise 'active_record_views metadata dump failed' unless $?.success?
  end
end
