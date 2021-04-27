require 'spec_helper'

describe 'rake tasks' do
  def rake(task_name, production: false)
    system(*%W[
      rake
      -f spec/internal/Rakefile
      #{task_name}
      RAILS_ENV=#{production ? 'production' : 'development'}
    ])
    raise unless $?.success?
  end

  describe 'db:migrate' do
    def view_names
      ActiveRecord::Base.connection.select_values(<<~SQL.squish)
        SELECT table_name
        FROM information_schema.views
        WHERE table_schema = 'public'
      SQL
    end

    it 'does not create any database views' do
      expect(view_names).to be_empty
      rake 'db:migrate'
      expect(view_names).to be_empty
    end

    it 'creates database views in production mode' do
      expect(view_names).to be_empty
      rake 'db:migrate', production: true
      expect(view_names).to_not be_empty
    end

    context 'with unregistered view' do
      before do
        ActiveRecordViews.create_view ActiveRecord::Base.connection, 'old_view', 'OldView', 'SELECT 42 AS id'
      end

      it 'does not drop unregistered views' do
        expect(view_names).to include 'old_view'
        rake 'db:migrate'
        expect(view_names).to include 'old_view'
      end

      it 'drops unregistered views in production mode' do
        expect(view_names).to include 'old_view'
        rake 'db:migrate', production: true
        expect(view_names).to_not include 'old_view'
      end
    end
  end

  describe 'db:structure:dump' do
    before do
      FileUtils.rm_f 'spec/internal/db/structure.sql'

      ActiveRecordViews.create_view ActiveRecord::Base.connection, 'test_view', 'TestView', 'SELECT 1'
    end

    after do
      FileUtils.rm_f 'spec/internal/db/structure.sql'
    end

    it 'copies over activerecord_views data' do
      rake 'db:structure:dump'

      sql = File.read('spec/internal/db/structure.sql')
      expect(sql).to match(/COPY public\.active_record_views.+test_view\tTestView/m)
      expect(sql).to match(/UPDATE public\.active_record_views SET refreshed_at = NULL/)
    end
  end
end
