module ActiveRecordViews
  class ChecksumCache
    def initialize(connection)
      @connection = connection
      init_state_table!
    end

    def init_state_table!
      table_exists = @connection.table_exists?('active_record_views')

      if table_exists && !@connection.column_exists?('active_record_views', 'class_name')
        @connection.transaction :requires_new => true do
          @connection.select_values('SELECT name FROM active_record_views;').each do |view_name|
            @connection.execute "DROP VIEW IF EXISTS #{view_name} CASCADE;"
          end
          @connection.execute 'DROP TABLE active_record_views;'
        end
        table_exists = false
      end

      unless table_exists
        @connection.execute 'CREATE TABLE active_record_views(name text PRIMARY KEY, class_name text NOT NULL UNIQUE, checksum text NOT NULL);'
      end
    end

    def get(name)
      @connection.select_one("SELECT class_name, checksum FROM active_record_views WHERE name = #{@connection.quote name}").try(:symbolize_keys)
    end

    def set(name, data)
      if data
        data.assert_valid_keys :class_name, :checksum

        rows_updated = @connection.update(<<-SQL)
          UPDATE active_record_views
          SET
            class_name = #{@connection.quote data[:class_name]},
            checksum = #{@connection.quote data[:checksum]}
          WHERE
            name = #{@connection.quote name}
          ;
        SQL

        if rows_updated == 0
          @connection.insert <<-SQL
            INSERT INTO active_record_views (
              name,
              class_name,
              checksum
            ) VALUES (
              #{@connection.quote name},
              #{@connection.quote data[:class_name]},
              #{@connection.quote data[:checksum]}
            )
          SQL
        end
      else
        @connection.delete "DELETE FROM active_record_views WHERE name = #{@connection.quote name}"
      end
    end
  end
end
