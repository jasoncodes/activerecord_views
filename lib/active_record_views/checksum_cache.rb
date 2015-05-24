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

      if table_exists && !@connection.column_exists?('active_record_views', 'options')
        @connection.execute "ALTER TABLE active_record_views ADD COLUMN options json NOT NULL DEFAULT '{}';"
      end

      if table_exists && !@connection.column_exists?('active_record_views', 'refreshed_at')
        @connection.execute "ALTER TABLE active_record_views ADD COLUMN refreshed_at timestamp;"
      end

      unless table_exists
        @connection.execute "CREATE TABLE active_record_views(name text PRIMARY KEY, class_name text NOT NULL UNIQUE, checksum text NOT NULL, options json NOT NULL DEFAULT '{}', refreshed_at timestamp);"
      end
    end

    def get(name)
      if data = @connection.select_one("SELECT class_name, checksum, options FROM active_record_views WHERE name = #{@connection.quote name}")
        data.symbolize_keys!
        data[:options] = JSON.load(data[:options]).symbolize_keys
        data
      end
    end

    def set(name, data)
      if data
        data.assert_valid_keys :class_name, :checksum, :options

        options = data[:options] || {}
        unless options.keys.all? { |key| key.is_a?(Symbol) }
          raise ArgumentError, 'option keys must be symbols'
        end
        options_json = JSON.dump(options)

        rows_updated = @connection.update(<<-SQL.squish)
          UPDATE active_record_views
          SET
            class_name = #{@connection.quote data[:class_name]},
            checksum = #{@connection.quote data[:checksum]},
            options = #{@connection.quote options_json}
          WHERE
            name = #{@connection.quote name}
          ;
        SQL

        if rows_updated == 0
          @connection.insert <<-SQL.squish
            INSERT INTO active_record_views (
              name,
              class_name,
              checksum,
              options
            ) VALUES (
              #{@connection.quote name},
              #{@connection.quote data[:class_name]},
              #{@connection.quote data[:checksum]},
              #{@connection.quote options_json}
            )
          SQL
        end
      else
        @connection.delete "DELETE FROM active_record_views WHERE name = #{@connection.quote name}"
      end
    end
  end
end
