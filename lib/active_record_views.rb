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
    require 'active_record_views/database_cleaner/truncation_extension' if defined? ::DatabaseCleaner
  end

  def self.find_sql_file(name)
    self.sql_load_path.each do |dir|
      path = "#{dir}/views/#{name}.sql"
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

    states = Thread.current[:active_record_views_without_transaction] ||= {}

    begin
      if states[connection]
        yield states[connection]
      elsif in_transaction
        begin
          temp_connection = connection.pool.checkout
          states[temp_connection] = states[connection] = temp_connection
          yield temp_connection
        ensure
          connection.pool.checkin temp_connection
          states[temp_connection] = states[connection] = nil
        end
      else
        begin
          states[connection] = connection
          yield connection
        ensure
          states[connection] = nil
        end
      end
    end
  end

  def self.create_view(base_connection, name, class_name, sql, options = {})
    options = options.dup
    options.assert_valid_keys :dependencies, :materialized, :unique_columns, :indexes
    options[:dependencies] = parse_dependencies(options[:dependencies])

    without_transaction base_connection do |connection|
      cache = ActiveRecordViews::ChecksumCache.new(connection)
      data = {class_name: class_name, checksum: Digest::SHA1.hexdigest(sql), options: options}
      return if cache.get(name) == data

      drop_and_create = if options[:materialized]
        true
      else
        raise ArgumentError, 'unique_columns option requires view to be materialized' if options[:unique_columns]
        begin
          connection.transaction :requires_new => true do
            connection.execute "CREATE OR REPLACE VIEW #{connection.quote_table_name name} AS #{sql}"
            check_dependencies connection, name, class_name, options[:dependencies]
          end
          false
        rescue ActiveRecord::StatementInvalid
          true
        end
      end

      if drop_and_create
        connection.transaction :requires_new => true do
          without_dependants connection, name do
            execute_drop_view connection, name
            execute_create_view connection, name, sql, options
            check_dependencies connection, name, class_name, options[:dependencies]
          end
        end
      end

      cache.set name, data
    end
  end

  def self.parse_dependencies(dependencies)
    dependencies = Array(dependencies)
    unless dependencies.all? { |dependency| dependency.is_a?(Class) && dependency < ActiveRecord::Base }
      raise ArgumentError, 'dependencies must be ActiveRecord classes'
    end
    dependencies.map(&:name).sort
  end

  def self.check_dependencies(connection, name, class_name, declared_class_names)
    actual_class_names = get_view_direct_dependencies(connection, name).sort

    missing_class_names = actual_class_names - declared_class_names
    extra_class_names = declared_class_names - actual_class_names

    if missing_class_names.present?
      example = "is_view dependencies: [#{actual_class_names.join(', ')}]"
      raise ArgumentError, <<-TEXT.squish
        #{missing_class_names.to_sentence}
        must be specified as
        #{missing_class_names.size > 1 ? 'dependencies' : 'a dependency'}
        of #{class_name}:
        `#{example}`
      TEXT
    end

    if extra_class_names.present?
      raise ArgumentError, <<-TEXT.squish
        #{extra_class_names.to_sentence}
        #{extra_class_names.size > 1 ? 'are' : 'is'}
        not
        #{extra_class_names.size > 1 ? 'dependencies' : 'a dependency'}
        of
        #{class_name}
      TEXT
    end
  end

  def self.drop_view(base_connection, name)
    without_transaction base_connection do |connection|
      cache = ActiveRecordViews::ChecksumCache.new(connection)
      execute_drop_view connection, name
      cache.set name, nil
    end
  end

  def self.drop_all_views(connection)
    names = Set.new connection.select_values('SELECT name FROM active_record_views;')

    func = lambda do |name|
      if view_exists?(connection, name)
        get_view_dependants(connection, name).each do |dependant_name, _, _, _|
          func.call(dependant_name)
        end
        drop_view connection, name
      end
    end

    names.each { |name| func.call(name) }
  end

  def self.execute_create_view(connection, name, sql, options)
    options.assert_valid_keys :dependencies, :materialized, :unique_columns, :indexes
    sql = sql.sub(/;\s*\z/, '')

    if options[:materialized]
      connection.execute "CREATE MATERIALIZED VIEW #{connection.quote_table_name name} AS #{sql} WITH NO DATA;"
    else
      connection.execute "CREATE VIEW #{connection.quote_table_name name} AS #{sql};"
    end

    if options[:indexes]
      options[:indexes].map { |column_name|
        connection.execute <<-SQL.squish
          CREATE INDEX #{connection.quote_table_name "#{name}_#{column_name}_index"}
          ON #{connection.quote_table_name name} (
            #{connection.quote_table_name(column_name)}
          )
        SQL
      }
    end

    if options[:unique_columns]
      connection.execute <<-SQL.squish
        CREATE UNIQUE INDEX #{connection.quote_table_name "#{name}_pkey"}
        ON #{connection.quote_table_name name}(
          #{options[:unique_columns].map { |column_name| connection.quote_table_name(column_name) }.join(', ')}
        );
      SQL
    end
  end

  def self.execute_drop_view(connection, name)
    if materialized_view?(connection, name)
      connection.execute "DROP MATERIALIZED VIEW IF EXISTS #{connection.quote_table_name name};"
    else
      connection.execute "DROP VIEW IF EXISTS #{connection.quote_table_name name};"
    end
  end

  def self.view_exists?(connection, name)
    connection.select_value(<<-SQL.squish).present?
      SELECT 1
      FROM information_schema.views
      WHERE table_schema = 'public' AND table_name = #{connection.quote name}
      UNION ALL
      SELECT 1
      FROM pg_matviews
      WHERE schemaname = 'public' AND matviewname = #{connection.quote name};
    SQL
  end

  def self.materialized_view?(connection, name)
    connection.select_value(<<-SQL.squish).present?
      SELECT 1
      FROM pg_matviews
      WHERE schemaname = 'public' AND matviewname = #{connection.quote name};
    SQL
  end

  def self.supports_concurrent_refresh?(connection)
    connection.raw_connection.server_version >= 90400
  end

  def self.get_view_direct_dependencies(connection, name)
    connection.select_values <<-SQL.squish
      WITH dependencies AS (
        SELECT DISTINCT refobjid::regclass::text AS name
        FROM pg_depend d
        INNER JOIN pg_rewrite r ON r.oid = d.objid
        WHERE refclassid = 'pg_class'::regclass
        AND classid = 'pg_rewrite'::regclass
        AND deptype = 'n'
        AND refobjid != r.ev_class
        AND r.ev_class = #{connection.quote name}::regclass::oid
      )

      SELECT class_name
      FROM dependencies
      INNER JOIN active_record_views USING (name)
    SQL
  end

  def self.get_view_dependants(connection, name)
    connection.select_rows <<-SQL.squish
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
        MIN(class_name) AS class_name,
        pg_catalog.pg_get_viewdef(oid) AS definition,
        MIN(options::text) AS options_json
      FROM dependants
      INNER JOIN active_record_views ON active_record_views.name = oid::regclass::text
      WHERE level > 0
      GROUP BY oid
      ORDER BY MAX(level)
      ;
    SQL
  end

  def self.without_dependants(connection, name)
    unless view_exists?(connection, name)
      yield
      return
    end

    dependants = get_view_dependants(connection, name)
    cache = ActiveRecordViews::ChecksumCache.new(connection)
    dependant_metadata = {}

    dependants.reverse.each do |dependant_name, _, _, _|
      execute_drop_view connection, dependant_name
      dependant_metadata[dependant_name] = cache.get(dependant_name)
      cache.set dependant_name, nil
    end

    yield

    dependants.each do |dependant_name, class_name, definition, options_json|
      create_view_exception = begin
        connection.transaction :requires_new => true do
          options = JSON.load(options_json).symbolize_keys
          execute_create_view connection, dependant_name, definition, options
          cache.set dependant_name, dependant_metadata[dependant_name]
        end
        nil
      rescue StandardError => e
        e
      end

      begin
        class_name.constantize
      rescue NameError => e
        raise unless e.missing_name?(class_name)
        raise create_view_exception unless create_view_exception.nil?
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
