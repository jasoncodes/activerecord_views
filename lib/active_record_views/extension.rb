module ActiveRecordViews
  module Extension
    extend ActiveSupport::Concern

    def self.currently_migrating?
      if defined?(Rake) && Rake.method_defined?(:application)
        Rake.application.top_level_tasks.include?('db:migrate')
      end
    end

    module ClassMethods
      def is_view(sql = nil)
        sql ||= begin
          sql_path = ActiveRecordViews.find_sql_file(self.name.underscore)
          ActiveRecordViews.register_for_reload self, sql_path
          File.read sql_path
        end
        unless ActiveRecordViews::Extension.currently_migrating?
          ActiveRecordViews.create_view self.connection, self.table_name, sql
        end
      end
    end
  end
end
