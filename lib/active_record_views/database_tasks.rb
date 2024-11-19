module ActiveRecordViews::DatabaseTasks
  def migrate(...)
    super

    unless ActiveRecordViews::Extension.create_enabled
      Rails.application.eager_load!
      ActiveRecordViews::Extension.process_create_queue!
      ActiveRecordViews.drop_unregistered_views!
    end
  end

  def dump_schema(db_config, format = ActiveRecord.respond_to?(:schema_format) ? ActiveRecord.schema_format : ActiveRecord::Base.schema_format, *args)
    super

    return unless format == :sql

    connection = if respond_to?(:migration_connection)
      migration_connection
    else
      ActiveRecord::Base.connection
    end
    return unless connection.data_source_exists?('active_record_views')

    filename = case
    when respond_to?(:schema_dump_path)
      schema_dump_path(db_config, format)
    when respond_to?(:dump_filename)
      spec_name = args.first
      dump_filename(spec_name || db_config.name, format)
    else
      raise 'unsupported ActiveRecord version'
    end

    adapter = case
    when respond_to?(:database_adapter_for)
      database_adapter_for(db_config)
    when respond_to?(:class_for_adapter, true)
      adapter_name = if db_config.respond_to?(:adapter)
        db_config.adapter
      else
        db_config.fetch('adapter')
      end
      class_for_adapter(adapter_name).new(db_config)
    else
      raise 'unsupported ActiveRecord version'
    end

    database_name = if db_config.respond_to?(:database)
      db_config.database
    else
      db_config.fetch('database')
    end

    active_record_views_dump = Tempfile.open(['active_record_views_dump', '.sql'])
    adapter.send(:run_cmd, 'pg_dump', %W[--data-only --no-owner --table=active_record_views #{database_name} -f #{active_record_views_dump.path}], 'dumping')
    adapter.send(:remove_sql_header_comments, active_record_views_dump.path)

    active_record_views_dump_content = active_record_views_dump.read

    # Substitute out any timestamps that were dumped from the active_record_views table
    #
    # Before:
    #
    #     COPY public.active_record_views (name, class_name, checksum, options, refreshed_at) FROM stdin;
    #     test_view       TestView        42364a017b73ef516a0eca9827e6fa00623257ee        {"dependencies":[]}     2021-10-26 02:49:12.247494
    #     \.
    #
    # After:
    #
    #     COPY public.active_record_views (name, class_name, checksum, options, refreshed_at) FROM stdin;
    #     test_view       TestView        42364a017b73ef516a0eca9827e6fa00623257ee        {"dependencies":[]}     \N
    #     \.
    if active_record_views_dump_content !~ /^COPY public.active_record_views \(.+, refreshed_at\) FROM stdin;$/
      raise 'refreshed_at is not final column'
    end
    active_record_views_dump_content.gsub!(/\t\d\d\d\d-\d\d-\d\d.*$/, "\t\\N")

    active_record_views_dump_content = active_record_views_dump_content
      .lines
      .chunk { |line| line.include?("\t") }
      .flat_map { |is_data, lines| is_data ? lines.sort : lines }
      .join

    File.open filename, 'a' do |io|
      io.puts active_record_views_dump_content
    end
  ensure
    active_record_views_dump&.close
    active_record_views_dump&.unlink
  end
end
