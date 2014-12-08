require 'spec_helper'

describe ActiveRecordViews do
  describe '.create_view' do
    let(:connection) { ActiveRecord::Base.connection }

    def create_test_view(sql)
      ActiveRecordViews.create_view connection, 'test', 'Test', sql
    end

    def test_view_sql
      connection.select_value(<<-SQL).try(&:squish)
        SELECT view_definition
        FROM information_schema.views
        WHERE table_schema = 'public' AND table_name = 'test'
      SQL
    end

    def view_names
      connection.select_values <<-SQL
        SELECT table_name
        FROM information_schema.views
        WHERE table_schema = 'public'
      SQL
    end

    it 'creates database view' do
      expect(test_view_sql).to be_nil
      create_test_view 'select 1 as id'
      expect(test_view_sql).to eq 'SELECT 1 AS id;'
    end

    it 'records checksum and class name' do
      create_test_view 'select 1 as id'
      expect(connection.select_all('select * from active_record_views').to_a).to eq [
        {
          'name' => 'test',
          'class_name' => 'Test',
          'checksum' => Digest::SHA1.hexdigest('select 1 as id')
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
          ActiveRecordViews.create_view connection, 'dependency1', 'Dependency1', 'SELECT id FROM test;'
          ActiveRecordViews.create_view connection, 'dependency2a', 'Dependency2a', 'SELECT id, id * 2 AS id2 FROM dependency1;'
          ActiveRecordViews.create_view connection, 'dependency2b', 'Dependency2b', 'SELECT id, id * 4 AS id4 FROM dependency1;'
          ActiveRecordViews.create_view connection, 'dependency3', 'Dependency3', 'SELECT * FROM dependency2b;'
          ActiveRecordViews.create_view connection, 'dependency4', 'Dependency4', 'SELECT id FROM dependency1 UNION ALL SELECT id FROM dependency3;'
        end

        after do
          dependants = %w[test dependency1 dependency2a dependency2b dependency3 dependency4]
          expect(view_names).to match_array dependants
          dependants.reverse.each do |name|
            ActiveRecordViews.drop_view connection, name
          end
        end

        it 'updates view with compatible change' do
          create_test_view 'select 2 as id'
          expect(test_view_sql).to eq 'SELECT 2 AS id;'
          expect(connection.select_value('SELECT id2 FROM dependency2a')).to eq '4'
        end

        describe 'changes incompatible with CREATE OR REPLACE' do
          it 'updates view with new column added before existing' do
            create_test_view "select 'foo'::text as name, 3 as id"
            expect(test_view_sql).to eq "SELECT 'foo'::text AS name, 3 AS id;"
            expect(connection.select_value('SELECT id2 FROM dependency2a')).to eq '6'
          end

          it 'fails to update view if column used by dependant view is removed' do
            expect {
              create_test_view "select 'foo'::text as name"
            }.to raise_error ActiveRecord::StatementInvalid, /column test.id does not exist/
            expect(test_view_sql).to eq 'SELECT 1 AS id;'
            expect(connection.select_value('SELECT id2 FROM dependency2a')).to eq '2'
          end
        end
      end

      describe 'with unmanaged dependant view' do
        before do
          connection.execute 'CREATE VIEW dependency AS SELECT id FROM test'
        end

        after do
          connection.execute 'DROP VIEW dependency;'
        end

        it 'updates view with compatible change' do
          create_test_view 'select 2 as id'
          expect(test_view_sql).to eq 'SELECT 2 AS id;'
        end

        it 'fails to update view with incompatible change' do
          expect {
            create_test_view "SELECT 'foo'::text as name, 4 as id"
          }.to raise_error ActiveRecord::StatementInvalid, /view dependency depends on view test/
          expect(test_view_sql).to eq 'SELECT 1 AS id;'
        end
      end
    end
  end
end
