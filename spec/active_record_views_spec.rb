require 'spec_helper'

describe ActiveRecordViews do
  describe '.create_view' do
    let(:connection) { ActiveRecord::Base.connection }

    def create_test_view(sql)
      ActiveRecordViews.create_view connection, 'test', sql
    end

    def test_view_sql
      connection.select_value <<-SQL
        SELECT view_definition
        FROM information_schema.views
        WHERE table_name = 'test'
      SQL
    end

    it 'creates database view' do
      expect(test_view_sql).to be_nil
      create_test_view 'select 1 as id'
      expect(test_view_sql).to eq 'SELECT 1 AS id;'
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

      context 'having a dependant view' do
        before do
          connection.execute 'CREATE VIEW dependency AS SELECT * FROM test'
        end

        after do
          connection.execute 'DROP VIEW dependency'
        end

        it 'updates view with compatible change' do
          create_test_view 'select 2 as id'
          expect(test_view_sql).to eq 'SELECT 2 AS id;'
        end

        it 'fails to update view with incompatible signature change' do
          expect {
            create_test_view "select 'foo'::text as name"
          }.to raise_error ActiveRecord::StatementInvalid, /cannot change name of view column/
          expect(test_view_sql).to eq 'SELECT 1 AS id;'
        end
      end
    end
  end
end
