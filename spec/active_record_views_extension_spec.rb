require 'spec_helper'

describe ActiveRecordViews::Extension do
  describe '.is_view' do
    it 'creates database views from heredocs' do
      expect(ActiveRecordViews).to receive(:create_view).once.and_call_original
      expect(HeredocTestModel.first.name).to eq 'Here document'
    end

    it 'creates database views from external SQL files' do
      expect(ActiveRecordViews).to receive(:create_view).once.and_call_original
      expect(ExternalFileTestModel.first.name).to eq 'External SQL file'
    end

    it 'creates database views from namespaced external SQL files' do
      expect(ActiveRecordViews).to receive(:create_view).once.and_call_original
      expect(Namespace::TestModel.first.name).to eq 'Namespaced SQL file'
    end

    it 'creates database views from external ERB files' do
      expect(ActiveRecordViews).to receive(:create_view).once.and_call_original
      expect(ErbTestModel.first.name).to eq 'ERB file'
    end

    it 'errors if external SQL file is missing' do
      expect {
        MissingFileTestModel
      }.to raise_error RuntimeError, /could not find missing_file_test_model.sql/
    end

    it 'reloads the database view when external SQL file is modified' do
      %w[foo bar baz].each do |sql|
        expect(ActiveRecordViews).to receive(:create_view).with(
          anything,
          'modified_file_test_models',
          'ModifiedFileTestModel',
          sql,
          {}
        ).once.ordered
      end

      with_temp_sql_dir do |temp_dir|
        sql_file = File.join(temp_dir, 'modified_file_test_model.sql')
        update_file sql_file, 'foo'

        class ModifiedFileTestModel < ActiveRecord::Base
          is_view
        end

        update_file sql_file, 'bar'

        test_request
        test_request # second request does not `create_view` again

        update_file sql_file, 'baz'

        test_request
      end
      test_request # trigger cleanup
    end

    it 'drops the view if the external SQL file is deleted' do
      with_temp_sql_dir do |temp_dir|
        sql_file = File.join(temp_dir, 'deleted_file_test_model.sql')
        File.write sql_file, "SELECT 1 AS id, 'delete test'::text AS name"

        class DeletedFileTestModel < ActiveRecord::Base
          is_view
        end

        expect(DeletedFileTestModel.first.name).to eq 'delete test'

        File.unlink sql_file

        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ADROP/).once.and_call_original
        test_request
        test_request # second request does not `drop_view` again

        expect {
          DeletedFileTestModel.first.name
        }.to raise_error ActiveRecord::StatementInvalid, /relation "deleted_file_test_models" does not exist/
      end
    end

    it 'does not create if database view is initially up to date' do
      ActiveRecordViews.create_view ActiveRecord::Base.connection, 'initial_create_test_models', 'InitialCreateTestModel', 'SELECT 42 as id'
      expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ACREATE (?:OR REPLACE )?VIEW/).never
      class InitialCreateTestModel < ActiveRecord::Base
        is_view 'SELECT 42 as id'
      end
    end

    it 'successfully recreates modified paired views with incompatible changes' do
      without_dependency_checks do
        ActiveRecordViews.create_view ActiveRecord::Base.connection, 'modified_as', 'ModifiedA', 'SELECT 11 AS old_name;'
        ActiveRecordViews.create_view ActiveRecord::Base.connection, 'modified_bs', 'ModifiedB', 'SELECT old_name FROM modified_as;'
      end

      expect(ModifiedB.first.attributes.except(nil)).to eq('new_name' => 22)
    end

    it 'successfully restores dependant view when temporarily dropping dependency' do
      without_dependency_checks do
        ActiveRecordViews.create_view ActiveRecord::Base.connection, 'dependency_as', 'DependencyA', 'SELECT 42 AS foo, 1 AS id;'
        ActiveRecordViews.create_view ActiveRecord::Base.connection, 'dependency_bs', 'DependencyB', 'SELECT id FROM dependency_as;'
      end

      expect(DependencyA.first.id).to eq 2
      expect(DependencyB.first.id).to eq 2
    end

    it 'sucessfully restore dependant view and dependency when loading from middle outwards' do
      without_dependency_checks do
        ActiveRecordViews.create_view ActiveRecord::Base.connection, 'dependency_as', 'DependencyA', 'SELECT 42 AS foo, 1 AS id;'
        ActiveRecordViews.create_view ActiveRecord::Base.connection, 'dependency_bs', 'DependencyB', 'SELECT id FROM dependency_as;'
        ActiveRecordViews.create_view ActiveRecord::Base.connection, 'dependency_cs', 'DependencyC', 'SELECT id FROM dependency_bs;'
      end

      expect(DependencyB.first.id).to eq 2
    end

    it 'errors if more than one argument is specified' do
      expect {
        class TooManyArguments < ActiveRecord::Base
          is_view 'SELECT 1 AS ID;', 'SELECT 2 AS ID;'
        end
      }.to raise_error ArgumentError, 'wrong number of arguments (2 for 0..1)'
    end

    it 'errors if an invalid option is specified' do
      expect {
        class InvalidOption < ActiveRecord::Base
          is_view 'SELECT 1 AS ID;', blargh: 123
        end
      }.to raise_error ArgumentError, /^Unknown key: :?blargh/
    end

    it 'creates/refreshes/drops materialized views' do
      with_temp_sql_dir do |temp_dir|
        sql_file = File.join(temp_dir, 'materialized_view_test_model.sql')
        File.write sql_file, 'SELECT 123 AS id;'

        class MaterializedViewTestModel < ActiveRecord::Base
          is_view materialized: true
        end

        expect {
          MaterializedViewTestModel.first!
        }.to raise_error ActiveRecord::StatementInvalid, /materialized view "materialized_view_test_models" has not been populated/

        expect(MaterializedViewTestModel.view_populated?).to eq false
        MaterializedViewTestModel.refresh_view!
        expect(MaterializedViewTestModel.view_populated?).to eq true

        expect(MaterializedViewTestModel.first!.id).to eq 123

        File.unlink sql_file
        test_request

        expect {
          MaterializedViewTestModel.first!
        }.to raise_error ActiveRecord::StatementInvalid, /relation "materialized_view_test_models" does not exist/
      end
    end

    it 'raises an error for `view_populated?` if view is not materialized' do
      class NonMaterializedViewPopulatedTestModel < ActiveRecord::Base
        is_view 'SELECT 1 AS id;'
      end

      expect {
        NonMaterializedViewPopulatedTestModel.view_populated?
      }.to raise_error ArgumentError, 'not a materialized view'
    end

    it 'supports refreshing materialized views concurrently' do
      class MaterializedViewRefreshTestModel < ActiveRecord::Base
        is_view 'SELECT 1 AS id;', materialized: true
      end
      class MaterializedViewConcurrentRefreshTestModel < ActiveRecord::Base
        is_view 'SELECT 1 AS id;', materialized: true, unique_columns: [:id]
      end
      MaterializedViewConcurrentRefreshTestModel.refresh_view!

      expect(ActiveRecord::Base.connection).to receive(:execute).with('REFRESH MATERIALIZED VIEW "materialized_view_refresh_test_models";').once.and_call_original
      expect(ActiveRecord::Base.connection).to receive(:execute).with('REFRESH MATERIALIZED VIEW CONCURRENTLY "materialized_view_concurrent_refresh_test_models";').once.and_call_original

      MaterializedViewRefreshTestModel.refresh_view!
      MaterializedViewConcurrentRefreshTestModel.refresh_view! concurrent: true
    end

    it 'supports opportunistically refreshing materialized views concurrently' do
      class MaterializedViewAutoRefreshTestModel < ActiveRecord::Base
        is_view 'SELECT 1 AS id;', materialized: true, unique_columns: [:id]
      end

      expect(ActiveRecord::Base.connection).to receive(:execute).with('REFRESH MATERIALIZED VIEW "materialized_view_auto_refresh_test_models";').once.and_call_original
      expect(ActiveRecord::Base.connection).to receive(:execute).with('REFRESH MATERIALIZED VIEW CONCURRENTLY "materialized_view_auto_refresh_test_models";').once.and_call_original

      MaterializedViewAutoRefreshTestModel.refresh_view! concurrent: :auto
      MaterializedViewAutoRefreshTestModel.refresh_view! concurrent: :auto
    end

    it 'raises an error when refreshing materialized views with invalid concurrent option' do
      class MaterializedViewInvalidRefreshTestModel < ActiveRecord::Base
        is_view 'SELECT 1 AS id;', materialized: true, unique_columns: [:id]
      end

      expect {
        MaterializedViewAutoRefreshTestModel.refresh_view! concurrent: :blah
      }.to raise_error ArgumentError, 'invalid concurrent option'
    end

    it 'errors if dependencies are not specified' do
      class DependencyCheckBase1 < ActiveRecord::Base
        self.table_name = 'dependency_check_base1'
        is_view 'SELECT 1 AS ID;'
      end
      class DependencyCheckBase2 < ActiveRecord::Base
        self.table_name = 'dependency_check_base2'
        is_view 'SELECT 1 AS ID;'
      end
      ActiveRecord::Base.connection.execute 'CREATE VIEW dependency_check_base_unmanaged AS SELECT 1 AS ID;'

      expect {
        class DependencyCheckGood < ActiveRecord::Base
          is_view 'SELECT * FROM dependency_check_base1;', dependencies: [DependencyCheckBase1]
        end
      }.to_not raise_error

      expect {
        class DependencyCheckGoodUnmanaged < ActiveRecord::Base
          is_view 'SELECT * FROM dependency_check_base_unmanaged;'
        end
      }.to_not raise_error

      expect {
        class DependencyCheckMissing1 < ActiveRecord::Base
          is_view 'SELECT * FROM dependency_check_base1 UNION ALL SELECT * FROM dependency_check_base2;', dependencies: [DependencyCheckBase1]
        end
      }.to raise_error ArgumentError, 'DependencyCheckBase2 must be specified as a dependency of DependencyCheckMissing1: `is_view dependencies: [DependencyCheckBase1, DependencyCheckBase2]`'

      expect {
        class DependencyCheckMissing2 < ActiveRecord::Base
          is_view 'SELECT * FROM dependency_check_base1 UNION ALL SELECT * FROM dependency_check_base2;', dependencies: []
        end
      }.to raise_error ArgumentError, 'DependencyCheckBase1 and DependencyCheckBase2 must be specified as dependencies of DependencyCheckMissing2: `is_view dependencies: [DependencyCheckBase1, DependencyCheckBase2]`'

      expect {
        class DependencyCheckNested < ActiveRecord::Base
          is_view 'SELECT 1 FROM dependency_check_goods'
        end
      }.to raise_error ArgumentError, 'DependencyCheckGood must be specified as a dependency of DependencyCheckNested: `is_view dependencies: [DependencyCheckGood]`'

      expect {
        class DependencyCheckExtra1 < ActiveRecord::Base
          is_view 'SELECT * FROM dependency_check_base1;', dependencies: [DependencyCheckBase1, DependencyCheckBase2]
        end
      }.to raise_error ArgumentError, 'DependencyCheckBase2 is not a dependency of DependencyCheckExtra1'

      expect {
        class DependencyCheckExtra2 < ActiveRecord::Base
          is_view 'SELECT 1 AS id;', dependencies: [DependencyCheckBase1, DependencyCheckBase2]
        end
      }.to raise_error ArgumentError, 'DependencyCheckBase1 and DependencyCheckBase2 are not dependencies of DependencyCheckExtra2'

      expect {
        class DependencyCheckWrongType < ActiveRecord::Base
          is_view 'SELECT 1;', dependencies: %w[DependencyCheckBase1]
        end
      }.to raise_error ArgumentError, 'dependencies must be ActiveRecord classes'

      expect(view_names).to match_array %w[
        dependency_check_base1
        dependency_check_base2
        dependency_check_base_unmanaged

        dependency_check_goods
        dependency_check_good_unmanageds
      ]
    end
  end
end
