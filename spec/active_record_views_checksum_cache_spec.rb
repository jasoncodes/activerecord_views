require 'spec_helper'

describe ActiveRecordViews::ChecksumCache do
  let(:connection) { ActiveRecord::Base.connection }

  describe 'initialisation' do
    context 'with no existing table' do
      it 'creates the table' do
        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ACREATE TABLE active_record_views/).once.and_call_original

        expect(connection.table_exists?('active_record_views')).to eq false
        ActiveRecordViews::ChecksumCache.new(connection)
        expect(connection.table_exists?('active_record_views')).to eq true
      end
    end

    context 'with existing table' do
      before do
        ActiveRecordViews::ChecksumCache.new(connection)
        expect(connection.table_exists?('active_record_views')).to eq true
      end

      it 'does not recreate the table' do
        expect(ActiveRecord::Base.connection).to receive(:execute).never

        ActiveRecordViews::ChecksumCache.new(connection)
      end
    end

    context 'with old table' do
      before do
        connection.execute 'CREATE TABLE active_record_views(name text PRIMARY KEY, checksum text NOT NULL);'
      end

      it 'recreates the table' do
        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ADROP TABLE active_record_views/).once.and_call_original
        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ACREATE TABLE active_record_views/).once.and_call_original

        expect(connection.column_exists?('active_record_views', 'class_name')).to eq false
        ActiveRecordViews::ChecksumCache.new(connection)
        expect(connection.column_exists?('active_record_views', 'class_name')).to eq true
      end
    end
  end
end
