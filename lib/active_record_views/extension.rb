require 'erb'

module ActiveRecordViews
  module Extension
    extend ActiveSupport::Concern

    mattr_accessor :create_enabled
    self.create_enabled = true

    mattr_accessor :create_queue
    self.create_queue = []

    def self.process_create_queue!
      while create_args = create_queue.shift
        ActiveRecordViews.create_view ActiveRecord::Base.connection, *create_args
      end
    end

    def self.currently_migrating?
      if defined?(Rake) && Rake.respond_to?(:application)
        Rake.application.top_level_tasks.any? { |task_name| task_name =~ /^db:migrate($|:)/ }
      end
    end

    module ClassMethods
      def is_view(*args)
        cattr_accessor :view_options
        self.view_options = args.extract_options!

        raise ArgumentError, "wrong number of arguments (#{args.size} for 0..1)" unless (0..1).cover?(args.size)
        sql = args.shift

        sql ||= begin
          sql_path = ActiveRecordViews.find_sql_file(self.name.underscore)
          ActiveRecordViews.register_for_reload self, sql_path
          ActiveRecordViews.read_sql_file(self, sql_path)
        end

        create_args = [self.table_name, self.name, sql, self.view_options]
        if ActiveRecordViews::Extension.create_enabled && !ActiveRecordViews::Extension.currently_migrating?
          ActiveRecordViews.create_view self.connection, *create_args
        else
          ActiveRecordViews::Extension.create_queue << create_args
        end
      end

      def refresh_view!(options = {})
        options.assert_valid_keys :concurrent

        concurrent = case options[:concurrent]
        when nil, false
          false
        when true
          true
        when :auto
          view_populated? && ActiveRecordViews.supports_concurrent_refresh?(connection)
        else
          raise ArgumentError, 'invalid concurrent option'
        end

        connection.transaction do
          connection.execute "REFRESH MATERIALIZED VIEW#{' CONCURRENTLY' if concurrent} #{connection.quote_table_name self.table_name};"
          connection.execute "UPDATE active_record_views SET refreshed_at = current_timestamp AT TIME ZONE 'UTC' WHERE name = #{connection.quote self.table_name};"
          connection.clear_query_cache
        end
      end

      def view_populated?
        value = connection.select_value(<<-SQL.squish)
          SELECT ispopulated
          FROM pg_matviews
          WHERE schemaname = 'public' AND matviewname = #{connection.quote self.table_name};
        SQL

        if value.nil?
          raise ArgumentError, 'not a materialized view'
        end

        if Rails::VERSION::MAJOR < 5
          value = ActiveRecord::ConnectionAdapters::Column::TRUE_VALUES.include?(value)
        end

        value
      end

      def refreshed_at
        value = connection.select_value(<<-SQL.squish)
          SELECT refreshed_at
          FROM active_record_views
          WHERE name = #{connection.quote self.table_name};
        SQL

        if value.is_a? String
          value = ActiveSupport::TimeZone['UTC'].parse(value)
        end

        value
      end

      def ensure_populated!
        ActiveRecordViews.get_view_direct_dependencies(self.connection, self.table_name).each do |class_name|
          klass = class_name.constantize
          klass.ensure_populated!
        end

        if ActiveRecordViews.materialized_view?(self.connection, self.table_name)
          refresh_view! unless view_populated?
        end
      end
    end
  end
end
