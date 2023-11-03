require 'spec_helper'

describe ActiveRecordViews do
  describe '.create_view' do
    let(:connection) { ActiveRecord::Base.connection }

    def create_test_view(sql, options = {})
      ActiveRecordViews.create_view connection, 'test', 'Test', sql, options
    end

    def drop_test_view
      ActiveRecordViews.drop_view connection, 'test'
    end

    def test_view_sql
      connection.select_value(<<-SQL.squish).try(&:squish)
        SELECT view_definition
        FROM information_schema.views
        WHERE table_schema = 'public' AND table_name = 'test'
      SQL
    end

    def test_view_populated?
      value = connection.select_value(<<~SQL)
        SELECT ispopulated
        FROM pg_matviews
        WHERE schemaname = 'public' AND matviewname = 'test'
      SQL

      value
    end

    def test_view_refreshed_at
      connection.select_value(<<~SQL)
        SELECT refreshed_at
        FROM active_record_views
        WHERE name = 'test'
      SQL
    end

    def test_materialized_view_sql
      connection.select_value(<<-SQL.squish).try(&:squish)
        SELECT definition
        FROM pg_matviews
        WHERE schemaname = 'public' AND matviewname = 'test'
      SQL
    end

    it 'creates database view' do
      expect(test_view_sql).to be_nil
      create_test_view 'select 1 as id'
      expect(test_view_sql).to eq 'SELECT 1 AS id;'
    end

    it 'records checksum, class name, and options' do
      create_test_view 'select 1 as id', materialized: true
      expect(connection.select_all('select * from active_record_views').to_a).to eq [
        {
          'name' => 'test',
          'class_name' => 'Test',
          'checksum' => Digest::SHA1.hexdigest('select 1 as id'),
          'options' => '{"materialized":true,"dependencies":[]}',
          'refreshed_at' => nil,
        }
      ]
    end

    it 'persists views if transaction rolls back' do
      expect(test_view_sql).to be_nil
      connection.transaction :requires_new => true do
        create_test_view 'select 1 as id'
        raise ActiveRecord::Rollback
      end
      expect(test_view_sql).to eq 'SELECT 1 AS id;'
    end

    it 'raises descriptive error if view SQL is invalid' do
      expect {
        create_test_view 'select blah'
      }.to raise_error ActiveRecord::StatementInvalid, /column "blah" does not exist/
    end

    context 'with existing view' do
      before do
        create_test_view 'select 1 as id'
        expect(test_view_sql).to eq 'SELECT 1 AS id;'
      end

      it 'updates view with compatible change' do
        create_test_view 'select 2 as id'
        expect(test_view_sql).to eq 'SELECT 2 AS id;'
      end

      it 'recreates view with incompatible change' do
        create_test_view "select 'foo'::text as name"
        expect(test_view_sql).to eq "SELECT 'foo'::text AS name;"
      end

      context 'having dependant views' do
        before do
          without_dependency_checks do
            ActiveRecordViews.create_view connection, 'dependant1', 'Dependant1', 'SELECT id FROM test;'
            ActiveRecordViews.create_view connection, 'dependant2a', 'Dependant2a', 'SELECT id, id * 2 AS id2 FROM dependant1;'
            ActiveRecordViews.create_view connection, 'dependant2b', 'Dependant2b', 'SELECT id, id * 4 AS id4 FROM dependant1;'
            ActiveRecordViews.create_view connection, 'dependant3', 'Dependant3', 'SELECT * FROM dependant2b;'
            ActiveRecordViews.create_view connection, 'dependant4', 'Dependant4', 'SELECT id FROM dependant1 UNION ALL SELECT id FROM dependant3;'
          end
        end

        it 'updates view with compatible change' do
          create_test_view 'select 2 as id'
          expect(test_view_sql).to eq 'SELECT 2 AS id;'
          expect(Integer(connection.select_value('SELECT id2 FROM dependant2a'))).to eq 4
        end

        describe 'changes incompatible with CREATE OR REPLACE' do
          it 'updates view with new column added before existing' do
            create_test_view "select 'foo'::text as name, 3 as id"
            expect(test_view_sql).to eq "SELECT 'foo'::text AS name, 3 AS id;"
            expect(Integer(connection.select_value('SELECT id2 FROM dependant2a'))).to eq 6
          end

          it 'fails to update view if column used by dependant view is removed' do
            expect {
              create_test_view "select 'foo'::text as name"
            }.to raise_error ActiveRecord::StatementInvalid, /^PG::UndefinedColumn:/
            expect(test_view_sql).to eq 'SELECT 1 AS id;'
            expect(Integer(connection.select_value('SELECT id2 FROM dependant2a'))).to eq 2
          end
        end

        describe '.drop_all_views' do
          it 'can drop all managed views' do
            connection.execute 'CREATE VIEW unmanaged AS SELECT 2 AS id;'

            expect(view_names).to match_array %w[test dependant1 dependant2a dependant2b dependant3 dependant4 unmanaged]
            ActiveRecordViews.drop_all_views connection
            expect(view_names).to match_array %w[unmanaged]
          end

          it 'support being ran inside a transaction' do
            expect(ActiveRecordViews).to receive(:without_transaction).at_least(:once).and_wrap_original do |original, *args, &block|
              original.call(*args) do |new_connection|
                new_connection.execute 'SET statement_timeout = 1000'
                block.call(new_connection)
              end
            end

            connection.transaction requires_new: true do
              expect {
                ActiveRecordViews.drop_all_views connection
              }.to change { view_names }
            end
          end

          it 'errors if an unmanaged view depends on a managed view' do
            connection.execute 'CREATE VIEW unmanaged AS SELECT * from dependant2a'

            expect {
              ActiveRecordViews.drop_all_views connection
            }.to raise_error ActiveRecord::StatementInvalid, /view unmanaged depends on view dependant2a/
          end

          it 'can drop materialized views' do
            without_dependency_checks do
              ActiveRecordViews.create_view connection, 'materialized', 'Materialized', 'SELECT id FROM test;', materialized: true
            end
            ActiveRecordViews.drop_all_views connection
            expect(view_names).to match_array %w[]
          end
        end
      end

      describe 'with unmanaged dependant view' do
        before do
          connection.execute 'CREATE VIEW dependant AS SELECT id FROM test'
        end

        after do
          connection.execute 'DROP VIEW dependant;'
        end

        it 'updates view with compatible change' do
          create_test_view 'select 2 as id'
          expect(test_view_sql).to eq 'SELECT 2 AS id;'
        end

        it 'fails to update view with incompatible change' do
          expect {
            create_test_view "SELECT 'foo'::text as name, 4 as id"
          }.to raise_error ActiveRecord::StatementInvalid, /view dependant depends on view test/
          expect(test_view_sql).to eq 'SELECT 1 AS id;'
        end
      end
    end

    it 'creates and drops materialized views' do
      create_test_view 'select 123 as id', materialized: true
      expect(test_view_sql).to eq nil
      expect(test_materialized_view_sql).to eq 'SELECT 123 AS id;'

      drop_test_view
      expect(test_view_sql).to eq nil
      expect(test_materialized_view_sql).to eq nil
    end

    it 'replaces a normal view with a materialized view' do
      create_test_view 'select 11 as id'
      create_test_view 'select 22 as id', materialized: true

      expect(test_view_sql).to eq nil
      expect(test_materialized_view_sql).to eq 'SELECT 22 AS id;'
    end

    it 'replaces a materialized view with a normal view' do
      create_test_view 'select 22 as id', materialized: true
      create_test_view 'select 11 as id'

      expect(test_view_sql).to eq 'SELECT 11 AS id;'
      expect(test_materialized_view_sql).to eq nil
    end

    it 'can test if materialized views can be refreshed concurrently' do
      expect(ActiveRecordViews.supports_concurrent_refresh?(connection)).to be true
    end

    it 'preserves materialized view if dropping/recreating' do
      without_dependency_checks do
        ActiveRecordViews.create_view connection, 'test1', 'Test1', 'SELECT 1 AS foo'
        ActiveRecordViews.create_view connection, 'test2', 'Test2', 'SELECT * FROM test1', materialized: true
        ActiveRecordViews.create_view connection, 'test1', 'Test1', 'SELECT 2 AS bar, 1 AS foo'
      end

      expect(materialized_view_names).to eq %w[test2]
      expect(view_names).to eq %w[test1]
    end

    it 'supports creating unique indexes on materialized views' do
      create_test_view 'select 1 as foo, 2 as bar, 3 as baz', materialized: true, unique_columns: [:foo, 'bar']
      index_sql = connection.select_value("SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'test_pkey';")
      expect(index_sql).to eq 'CREATE UNIQUE INDEX test_pkey ON public.test USING btree (foo, bar)'
    end

    it 'errors if trying to create unique index on non-materialized view' do
      expect {
        create_test_view 'select 1 as foo, 2 as bar, 3 as baz', materialized: false, unique_columns: [:foo, 'bar']
      }.to raise_error ArgumentError, 'unique_columns option requires view to be materialized'
    end

    it 'supports resetting all materialised views' do
      class ResetMaterializeViewTestModel < ActiveRecord::Base
        self.table_name = 'test'
        is_view 'select 123 as id', materialized: true
      end
      ResetMaterializeViewTestModel.refresh_view!

      expect {
        ActiveRecordViews.reset_materialized_views
      }.to change { test_view_populated? }.to(false)
        .and change { test_view_refreshed_at }.to(nil)
    end
  end

  describe '.drop_all_views' do
    let(:connection) { ActiveRecord::Base.connection }

    it 'does nothing when no views have been defined' do
      ActiveRecordViews.drop_all_views connection
      expect(view_names).to match_array %w[]
    end
  end

  describe '.without_transaction' do
    let(:original_connection) { ActiveRecord::Base.connection }

    it 'yields original connection if no active transaction' do
      ActiveRecordViews.without_transaction original_connection do |new_connection|
        expect(new_connection).to eq original_connection
      end
    end

    it 'yields a new connection if inside a transaction' do
      original_connection.transaction do
        ActiveRecordViews.without_transaction original_connection do |new_connection|
          expect(new_connection).to_not eq original_connection
        end
      end
    end

    it 'yields original connection if called recursively' do
      ActiveRecordViews.without_transaction original_connection do |new_connection_1|
        expect(new_connection_1).to eq original_connection
        new_connection_1.transaction do
          ActiveRecordViews.without_transaction new_connection_1 do |new_connection_2|
            expect(new_connection_2).to eq new_connection_1
          end
        end
      end
    end

    it 'yields same isolated connection if called recursively on original connection inside transaction' do
      original_connection.transaction do
        ActiveRecordViews.without_transaction original_connection do |new_connection_1|
          expect(new_connection_1).to_not eq original_connection
          ActiveRecordViews.without_transaction original_connection do |new_connection_2|
            expect(new_connection_2).to eq new_connection_1
          end
        end
      end
    end

    it 'yields different isolated connection if called recursively on different connections inside transcation' do
      begin
        original_connection_2 = original_connection.pool.checkout

        original_connection.transaction do
          ActiveRecordViews.without_transaction original_connection do |new_connection_1|
            expect(new_connection_1).to_not eq original_connection
            original_connection_2.transaction do
              ActiveRecordViews.without_transaction original_connection_2 do |new_connection_2|
                expect(new_connection_2).to_not eq original_connection
                expect(new_connection_2).to_not eq original_connection_2
                expect(new_connection_2).to_not eq new_connection_1
              end
            end
          end
        end
      ensure
        original_connection.pool.checkin original_connection_2
      end
    end

    it 'does not attempt to checkin when checkout fails' do
      expect(original_connection.pool).to receive(:checkout).and_raise PG::ConnectionBad
      expect(original_connection.pool).to_not receive(:checkin)

      expect {
        original_connection.transaction do
          ActiveRecordViews.without_transaction(original_connection) { }
        end
      }.to raise_error PG::ConnectionBad
    end
  end
end
