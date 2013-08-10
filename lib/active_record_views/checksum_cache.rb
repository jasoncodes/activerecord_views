module ActiveRecordViews
  class ChecksumCache
    def initialize(connection)
      @connection = connection
      init_state_table!
    end

    def init_state_table!
      unless @connection.table_exists?('active_record_views')
        @connection.execute 'CREATE TABLE active_record_views(name text PRIMARY KEY, checksum text NOT NULL);'
      end
    end

    def get(name)
      @connection.select_value("SELECT checksum FROM active_record_views WHERE name = #{@connection.quote name}")
    end

    def set(name, checksum)
      if checksum
        if @connection.update("UPDATE active_record_views SET checksum = #{@connection.quote checksum} WHERE name = #{@connection.quote name}") == 0
          @connection.insert "INSERT INTO active_record_views (name, checksum) VALUES (#{@connection.quote name}, #{@connection.quote checksum})"
        end
      else
        @connection.delete "DELETE FROM active_record_views WHERE name = #{@connection.quote name}"
      end
    end
  end
end
