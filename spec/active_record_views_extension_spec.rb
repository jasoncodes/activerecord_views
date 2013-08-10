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
    end
  end
end
