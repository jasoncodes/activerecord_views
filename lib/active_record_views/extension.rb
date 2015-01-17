require 'erb'

module ActiveRecordViews
  module Extension
    extend ActiveSupport::Concern

    def self.currently_migrating?
      if defined?(Rake) && Rake.method_defined?(:application)
        Rake.application.top_level_tasks.include?('db:migrate')
      end
    end

    module ClassMethods
      def is_view(*args)
        return if ActiveRecordViews::Extension.currently_migrating?

        cattr_accessor :view_options
        self.view_options = args.extract_options!

        raise ArgumentError, "wrong number of arguments (#{args.size} for 0..1)" unless (0..1).cover?(args.size)
        sql = args.shift

        sql ||= begin
          sql_path = ActiveRecordViews.find_sql_file(self.name.underscore)
          ActiveRecordViews.register_for_reload self, sql_path

          if sql_path.end_with?('.erb')
            ERB.new(File.read(sql_path)).result
          else
            File.read(sql_path)
          end
        end

        ActiveRecordViews.create_view self.connection, self.table_name, self.name, sql, self.view_options
      end
    end
  end
end
