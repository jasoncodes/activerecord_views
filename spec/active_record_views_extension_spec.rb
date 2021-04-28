require 'spec_helper'

describe ActiveRecordViews::Extension do
  describe '.is_view' do
    def registered_model_class_names
      ActiveRecordViews.registered_views.map(&:model_class_name)
    end

    def view_exists?(name)
      connection = ActiveRecord::Base.connection
      if connection.respond_to?(:view_exists?)
        connection.view_exists?(name)
      else
        connection.table_exists?(name)
      end
    end

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
      expect(ErbTestModel.first.name).to eq 'ERB method file'
    end

    it 'errors if external SQL file is missing' do
      expect {
        class MissingFileTestModel < ActiveRecord::Base
          is_view
        end
      }.to raise_error RuntimeError, /could not find missing_file_test_model.sql/
    end

    it 'reloads the database view when external SQL file is modified' do
      sql_file = File.join(TEST_TEMP_MODEL_DIR, 'modified_file_test_model.sql')
      update_file sql_file, "SELECT 'foo'::text AS test"

      expect {
        expect(ActiveRecordViews).to receive(:create_view).once.and_call_original
        class ModifiedFileTestModel < ActiveRecord::Base
          is_view
        end
      }.to change { begin; ModifiedFileTestModel.take!.test; rescue NameError; end }.from(nil).to('foo')
        .and change { registered_model_class_names.include?('ModifiedFileTestModel') }.from(false).to(true)

      expect {
        update_file sql_file, "SELECT 'bar'::text AS test, 42::integer AS test2"
      }.to_not change { ModifiedFileTestModel.take!.test }

      expect {
        expect(ActiveRecordViews).to receive(:create_view).once.and_call_original
        test_request
        test_request # second request does not `create_view` again
      }.to change { ModifiedFileTestModel.take!.test }.to('bar')
        .and change { ModifiedFileTestModel.column_names }.from(%w[test]).to(%w[test test2])

      expect {
        update_file sql_file, "SELECT 'baz'::text AS test"
      }.to_not change { ModifiedFileTestModel.take!.test }

      expect {
        expect(ActiveRecordViews).to receive(:create_view).once.and_call_original
        test_request
      }.to change { ModifiedFileTestModel.take!.test }.to('baz')

      File.unlink sql_file
      test_request # trigger cleanup
    end

    it 'reloads the database view when external ERB SQL file is modified' do
      ['foo 42', 'bar 42'].each do |sql|
        expect(ActiveRecordViews).to receive(:create_view).with(
          anything,
          'modified_erb_file_test_models',
          'ModifiedErbFileTestModel',
          sql,
          {}
        ).once.ordered
      end

      sql_file = File.join(TEST_TEMP_MODEL_DIR, 'modified_erb_file_test_model.sql.erb')
      update_file sql_file, 'foo <%= test_erb_method %>'

      class ModifiedErbFileTestModel < ActiveRecord::Base
        def self.test_erb_method
          2 * 3 * 7
        end

        is_view
      end

      update_file sql_file, 'bar <%= test_erb_method %>'
      test_request

      File.unlink sql_file
      test_request # trigger cleanup
    end

    it 'drops the view if the external SQL file is deleted' do
      sql_file = File.join(TEST_TEMP_MODEL_DIR, 'deleted_file_test_model.sql')
      File.write sql_file, "SELECT 1 AS id, 'delete test'::text AS name"

      rb_file = 'spec/internal/app/models_temp/deleted_file_test_model.rb'
      File.write rb_file, <<~RB
        class DeletedFileTestModel < ActiveRecord::Base
          is_view
        end
      RB

      with_reloader do
        expect(DeletedFileTestModel.first.name).to eq 'delete test'
      end

      File.unlink sql_file
      File.unlink rb_file

      expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ADROP/).once.and_call_original
      expect {
        test_request
      }.to change { registered_model_class_names.include?('DeletedFileTestModel') }.from(true).to(false)
        .and change { view_exists?('deleted_file_test_models') }.from(true).to(false)
      test_request # second request does not `drop_view` again

      if Rails::VERSION::MAJOR >= 5
        expect {
          DeletedFileTestModel.first.name
        }.to raise_error NameError, 'uninitialized constant DeletedFileTestModel'
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
      sql_file = File.join(TEST_TEMP_MODEL_DIR, 'materialized_view_test_model.sql')
      File.write sql_file, 'SELECT 123 AS id;'

      class MaterializedViewTestModel < ActiveRecord::Base
        is_view materialized: true
      end

      expect {
        MaterializedViewTestModel.first!
      }.to raise_error ActiveRecord::StatementInvalid, /materialized view "materialized_view_test_models" has not been populated/

      expect(MaterializedViewTestModel.view_populated?).to eq false
      expect(MaterializedViewTestModel.refreshed_at).to eq nil

      MaterializedViewTestModel.refresh_view!

      expect(MaterializedViewTestModel.view_populated?).to eq true
      expect(MaterializedViewTestModel.refreshed_at).to be_a Time
      expect(MaterializedViewTestModel.refreshed_at.zone).to eq 'UTC'
      expect(MaterializedViewTestModel.refreshed_at).to be_within(1.second).of Time.now

      expect(MaterializedViewTestModel.first!.id).to eq 123

      File.unlink sql_file

      expect {
        test_request
      }.to change { view_exists?('materialized_view_test_models') }.from(true).to(false)
    end

    it 'raises an error for `view_populated?` if view is not materialized' do
      class NonMaterializedViewPopulatedTestModel < ActiveRecord::Base
        is_view 'SELECT 1 AS id;'
      end

      expect {
        NonMaterializedViewPopulatedTestModel.view_populated?
      }.to raise_error ArgumentError, 'not a materialized view'
    end

    it 'supports ensuring a view hierarchy has been populated' do
      class EnsurePopulatedFoo < ActiveRecord::Base
        is_view 'SELECT 1 AS id;', materialized: true
      end

      class EnsurePopulatedBar < ActiveRecord::Base
        is_view "SELECT * FROM #{EnsurePopulatedFoo.table_name}", dependencies: [EnsurePopulatedFoo]
      end

      class EnsurePopulatedBaz < ActiveRecord::Base
        is_view "SELECT * FROM #{EnsurePopulatedBar.table_name}", dependencies: [EnsurePopulatedBar]
      end

      expect(ActiveRecord::Base.connection).to receive(:execute).with('REFRESH MATERIALIZED VIEW "ensure_populated_foos";').once.and_call_original
      allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original

      expect(EnsurePopulatedFoo.view_populated?).to eq false
      EnsurePopulatedBaz.ensure_populated!
      expect(EnsurePopulatedFoo.view_populated?).to eq true
      EnsurePopulatedBaz.ensure_populated!
      expect(EnsurePopulatedFoo.view_populated?).to eq true
    end

    it 'invalidates ActiveRecord query cache after populating' do
      class EnsurePopulatedCache < ActiveRecord::Base
        is_view 'SELECT 1 AS id;', materialized: true
      end

      expect(ActiveRecord::Base.connection).to receive(:execute).with('REFRESH MATERIALIZED VIEW "ensure_populated_caches";').once.and_call_original
      allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original

      ActiveRecord::Base.connection.cache do
        expect(EnsurePopulatedCache.view_populated?).to eq false
        EnsurePopulatedCache.ensure_populated!
        expect(EnsurePopulatedCache.view_populated?).to eq true
        EnsurePopulatedCache.ensure_populated!
        expect(EnsurePopulatedCache.view_populated?).to eq true
      end
    end

    it 'supports refreshing materialized views concurrently' do
      class MaterializedViewRefreshTestModel < ActiveRecord::Base
        is_view 'SELECT 1 AS id;', materialized: true
      end
      class MaterializedViewConcurrentRefreshTestModel < ActiveRecord::Base
        is_view 'SELECT 1 AS id;', materialized: true, unique_columns: [:id]
      end
      MaterializedViewConcurrentRefreshTestModel.refresh_view!

      [
        'BEGIN',
        'REFRESH MATERIALIZED VIEW "materialized_view_refresh_test_models";',
        "UPDATE active_record_views SET refreshed_at = current_timestamp AT TIME ZONE 'UTC' WHERE name = 'materialized_view_refresh_test_models';",
        'COMMIT',
        'BEGIN',
        'REFRESH MATERIALIZED VIEW CONCURRENTLY "materialized_view_concurrent_refresh_test_models";',
        "UPDATE active_record_views SET refreshed_at = current_timestamp AT TIME ZONE 'UTC' WHERE name = 'materialized_view_concurrent_refresh_test_models';",
        'COMMIT',
      ].each do |sql|
        extra_args = Gem::Version.new(Rails.version) >= Gem::Version.new("6.1") && %w[BEGIN COMMIT].include?(sql) ? %w[TRANSACTION] : %w[]
        expect(ActiveRecord::Base.connection).to receive(:execute).with(sql, *extra_args).once.and_call_original
      end

      MaterializedViewRefreshTestModel.refresh_view!
      MaterializedViewConcurrentRefreshTestModel.refresh_view! concurrent: true
    end

    it 'supports opportunistically refreshing materialized views concurrently' do
      class MaterializedViewAutoRefreshTestModel < ActiveRecord::Base
        is_view 'SELECT 1 AS id;', materialized: true, unique_columns: [:id]
      end

      [
        'BEGIN',
        'REFRESH MATERIALIZED VIEW "materialized_view_auto_refresh_test_models";',
        "UPDATE active_record_views SET refreshed_at = current_timestamp AT TIME ZONE 'UTC' WHERE name = 'materialized_view_auto_refresh_test_models';",
        'COMMIT',
        'BEGIN',
        'REFRESH MATERIALIZED VIEW CONCURRENTLY "materialized_view_auto_refresh_test_models";',
        "UPDATE active_record_views SET refreshed_at = current_timestamp AT TIME ZONE 'UTC' WHERE name = 'materialized_view_auto_refresh_test_models';",
        'COMMIT',
      ].each do |sql|
        extra_args = Gem::Version.new(Rails.version) >= Gem::Version.new("6.1") && %w[BEGIN COMMIT].include?(sql) ? %w[TRANSACTION] : %w[]
        expect(ActiveRecord::Base.connection).to receive(:execute).with(sql, *extra_args).once.and_call_original
      end

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

    context 'without create_enabled' do
      around do |example|
        without_create_enabled(&example)
      end

      it 'delays create_view until process_create_queue! is called' do
        allow(ActiveRecordViews).to receive(:create_view).and_call_original

        expect(ActiveRecordViews::Extension.create_queue.size).to eq 0
        expect(ActiveRecordViews).to_not have_received(:create_view)

        expect {
          expect(HeredocTestModel.first.name).to eq 'Here document'
        }.to raise_error ActiveRecord::StatementInvalid

        expect(ActiveRecordViews::Extension.create_queue.size).to eq 1
        expect(ActiveRecordViews).to_not have_received(:create_view)

        ActiveRecordViews::Extension.process_create_queue!

        expect(ActiveRecordViews::Extension.create_queue.size).to eq 0
        expect(ActiveRecordViews).to have_received(:create_view)

        expect(HeredocTestModel.first.name).to eq 'Here document'
      end
    end
  end
end
