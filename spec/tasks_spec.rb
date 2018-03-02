require 'spec_helper'

describe 'rake db:structure:dump' do
  it 'copies over activerecord_views data' do
    ActiveRecordViews.create_view ActiveRecord::Base.connection, 'test_view', 'TestView', 'SELECT 1'

    FileUtils.rm_f 'spec/internal/db/structure.sql'
    system("rake -f spec/internal/Rakefile db:structure:dump")
    raise unless $?.success?

    sql = File.read('spec/internal/db/structure.sql')
    FileUtils.rm_f 'spec/internal/db/structure.sql'

    expect(sql).to match(/COPY public\.active_record_views.+test_view\tTestView/m)
    expect(sql).to match(/UPDATE public\.active_record_views SET refreshed_at = NULL/)
  end
end
