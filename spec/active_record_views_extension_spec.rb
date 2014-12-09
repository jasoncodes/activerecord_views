require 'spec_helper'

describe ActiveRecordViews::Extension do
  describe '.as_view' do
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
          sql
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
      ActiveRecordViews.create_view ActiveRecord::Base.connection, 'modified_as', 'ModifiedA', 'SELECT 11 AS old_name;'
      ActiveRecordViews.create_view ActiveRecord::Base.connection, 'modified_bs', 'ModifiedB', 'SELECT old_name FROM modified_as;'

      expect(ModifiedB.first.attributes.except(nil)).to eq('new_name' => 22)
    end
  end
end
