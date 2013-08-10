module ActiveRecordViews
  class RegisteredView
    attr_reader :model_class, :sql_path

    def initialize(model_class, sql_path)
      @model_class_name = model_class.name
      @sql_path = sql_path
      update_timestamp!
    end

    def model_class
      @model_class_name.constantize
    end

    def stale?
      sql_timestamp != @cached_sql_timestamp
    end

    def reload!
      if File.exists? sql_path
        ActiveRecordViews.create_view model_class.connection, model_class.table_name, File.read(sql_path)
      else
        ActiveRecordViews.drop_view model_class.connection, model_class.table_name
      end
      update_timestamp!
    end

    private

    def sql_timestamp
      File.exists?(sql_path) ? File.mtime(sql_path) : nil
    end

    def update_timestamp!
      @cached_sql_timestamp = sql_timestamp
    end
  end
end
