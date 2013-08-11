require 'active_record'

module ActiveRecordViews
  class ChecksumCache
    class Model < ActiveRecord::Base
      self.table_name = 'active_record_views'
      self.primary_key = 'name'
    end

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
      Model.where(:name => name).first_or_initialize.checksum
    end

    def set(name, checksum)
      row = Model.where(:name => name).first_or_initialize
      if checksum
        row.update_attributes! :checksum => checksum
      else
        row.destroy
      end
    end
  end
end
