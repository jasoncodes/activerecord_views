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
      return path if File.exist?(path)
      path = path + '.erb'
      return path if File.exist?(path)
    end
    raise "could not find #{name}.sql"
  end

  def self.without_transaction(connection)
    in_transaction = if connection.respond_to? :transaction_open?
      connection.transaction_open?
    else
      !connection.outside_transaction?
    end

    begin
      recursing = Thread.current[:active_record_views_without_transaction]
      Thread.current[:active_record_views_without_transaction] = true

      if in_transaction && !recursing
        begin
          temp_connection = connection.pool.checkout
          yield temp_connection
        ensure
          connection.pool.checkin temp_connection
        end
      else
        yield connection
      end
    ensure
      Thread.current[:active_record_views_without_transaction] = nil
    end
  end

  def self.create_view(base_connection, name, class_name, sql)
    without_transaction base_connection do |connection|
      cache = ActiveRecordViews::ChecksumCache.new(connection)
      data = {class_name: class_name, checksum: Digest::SHA1.hexdigest(sql)}
      return if cache.get(name) == data

      begin
        connection.execute "CREATE OR REPLACE VIEW #{connection.quote_table_name name} AS #{sql}"
      rescue ActiveRecord::StatementInvalid
        raise unless view_exists?(connection, name)
        connection.transaction :requires_new => true do
          without_dependencies connection, name do
            execute_drop_view connection, name
            execute_create_view connection, name, sql
          end
        end
      end

      cache.set name, data
    end
  end

  def self.drop_view(base_connection, name)
    without_transaction base_connection do |connection|
      cache = ActiveRecordViews::ChecksumCache.new(connection)
      execute_drop_view connection, name
      cache.set name, nil
    end
  end

  def self.execute_create_view(connection, name, sql)
    connection.execute "CREATE VIEW #{connection.quote_table_name name} AS #{sql};"
  end

  def self.execute_drop_view(connection, name)
    connection.execute "DROP VIEW IF EXISTS #{connection.quote_table_name name};"
  end

  def self.view_exists?(connection, name)
    connection.select_value(<<-SQL).present?
      SELECT 1
      FROM information_schema.views
      WHERE table_schema = 'public' AND table_name = #{connection.quote name};
    SQL
  end

  def self.get_view_dependencies(connection, name)
    connection.select_rows <<-SQL
      WITH RECURSIVE dependants AS (
        SELECT
          #{connection.quote name}::regclass::oid,
          0 AS level

        UNION ALL

        SELECT
          DISTINCT(pg_rewrite.ev_class) AS oid,
          dependants.level + 1 AS level
        FROM pg_depend dep
        INNER JOIN pg_rewrite ON pg_rewrite.oid = dep.objid
        INNER JOIN dependants ON dependants.oid = dep.refobjid
        WHERE pg_rewrite.ev_class != dep.refobjid AND dep.deptype = 'n'
      )

      SELECT
        oid::regclass::text AS name,
        class_name,
        pg_catalog.pg_get_viewdef(oid) AS definition
      FROM dependants
      INNER JOIN active_record_views ON active_record_views.name = oid::regclass::text
      WHERE level > 0
      GROUP BY oid, class_name
      ORDER BY MAX(level)
      ;
    SQL
  end

  def self.without_dependencies(connection, name)
    dependencies = get_view_dependencies(connection, name)

    dependencies.reverse.each do |dependency_name, _, _|
      execute_drop_view connection, dependency_name
    end

    yield

    dependencies.each do |dependency_name, class_name, definition|
      begin
        class_name.constantize
      rescue NameError => e
        raise unless e.missing_name?(class_name)
        execute_create_view connection, dependency_name, definition
      end
    end
  end

  def self.register_for_reload(model_class, sql_path)
    self.registered_views << RegisteredView.new(model_class, sql_path)
  end

  def self.reload_stale_views!
    self.registered_views.each do |registered_view|
      if registered_view.stale?
        registered_view.reload!
      end
    end
  end
end
