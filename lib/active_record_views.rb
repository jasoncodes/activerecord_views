require 'active_record_views/version'
require 'active_record_views/railtie' if defined? Rails
require 'active_record_views/registered_view'
require 'active_record_views/checksum_cache'
require 'active_support/core_ext/module/attribute_accessors'
require 'digest/sha1'

module ActiveRecordViews
  mattr_accessor :sql_load_path
  self.sql_load_path = []

  mattr_accessor :registered_views
  self.registered_views = []

  def self.init!
    require 'active_record_views/extension'
    ::ActiveRecord::Base.send :include, ActiveRecordViews::Extension
  end

  def self.find_sql_file(name)
    self.sql_load_path.each do |dir|
      path = "#{dir}/#{name}.sql"
      return path if File.exists?(path)
    end
    raise "could not find #{name}.sql"
  end

  def self.create_view(connection, name, sql)
    cache = ActiveRecordViews::ChecksumCache.new(connection)
    checksum = Digest::SHA1.hexdigest(sql)
    return if cache.get(name) == checksum

    begin
      connection.execute "CREATE OR REPLACE VIEW #{connection.quote_table_name name} AS #{sql}"
    rescue ActiveRecord::StatementInvalid => original_exception
      begin
        connection.transaction :requires_new => true do
          connection.execute "DROP VIEW #{connection.quote_table_name name}"
          connection.execute "CREATE VIEW #{connection.quote_table_name name} AS #{sql}"
        end
      rescue
        raise original_exception
      end
    end

    cache.set name, checksum
  end

  def self.drop_view(connection, name)
    cache = ActiveRecordViews::ChecksumCache.new(connection)
    connection.execute "DROP VIEW IF EXISTS #{connection.quote_table_name name}"
    cache.set name, nil
  end

  def self.register_for_reload(sql_path, model_path)
    self.registered_views << RegisteredView.new(sql_path, model_path)
  end

  def self.reload_stale_views!
    self.registered_views.each do |registered_view|
      if registered_view.stale?
        registered_view.reload!
      end
    end
  end
end
