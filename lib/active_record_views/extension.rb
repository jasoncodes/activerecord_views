module ActiveRecordViews
  module Extension
    extend ActiveSupport::Concern

    module ClassMethods
      def is_view(sql = nil)
        sql ||= begin
          sql_path = ActiveRecordViews.find_sql_file(self.name.underscore)
          ActiveRecordViews.register_for_reload self, sql_path
          File.read sql_path
        end
        ActiveRecordViews.create_view self.connection, self.table_name, sql
      end
    end
  end
end
