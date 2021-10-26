require 'spec_helper'

describe 'rake tasks' do
  def rake(task_name, env: {})
    system(env, *%W[
      rake
      -f spec/internal/Rakefile
      #{task_name}
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
      rake 'db:migrate', env: {'RAILS_ENV' => 'production'}
      expect(view_names).to_not be_empty
    end

    it 'does nothing in production mode without models' do
      expect(view_names).to be_empty
      rake 'db:migrate', env: {'RAILS_ENV' => 'production', 'SKIP_MODEL_EAGER_LOAD' => 'true'}
      expect(view_names).to be_empty
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
        rake 'db:migrate', env: {'RAILS_ENV' => 'production'}
        expect(view_names).to_not include 'old_view'
      end
    end
  end

  schema_rake_task = Gem::Version.new(Rails.version) >= Gem::Version.new("6.1") ? 'db:schema:dump' : 'db:structure:dump'
  describe schema_rake_task do
    before do
      FileUtils.rm_f 'spec/internal/db/schema.rb'
      FileUtils.rm_f 'spec/internal/db/structure.sql'

      ActiveRecordViews.create_view ActiveRecord::Base.connection, 'test_view', 'TestView', 'SELECT 1'
    end

    after do
      FileUtils.rm_f 'spec/internal/db/schema.rb'
      FileUtils.rm_f 'spec/internal/db/structure.sql'

      File.write 'spec/internal/db/schema.rb', ''
    end

    it 'copies over activerecord_views data' do
      rake schema_rake_task

      expect(File.exist?('spec/internal/db/schema.rb')).to eq false
      sql = File.read('spec/internal/db/structure.sql')
      expect(sql).to match(/CREATE TABLE public\.schema_migrations/)
      expect(sql).to match(/CREATE VIEW public\.test_view/)
      expect(sql).to match(/COPY public\.active_record_views.+test_view\tTestView\t.*\t.*\t\\N$/m)
    end

    it 'clears refreshed_at values' do
      ActiveRecord::Base.connection.execute "UPDATE active_record_views SET refreshed_at = current_timestamp AT TIME ZONE 'UTC' WHERE name = 'test_view';"

      rake schema_rake_task

      ActiveRecord::Base.clear_all_connections!

      system 'dropdb activerecord_views_test'
      raise unless $?.success?
      system 'createdb activerecord_views_test'
      raise unless $?.success?
      system 'psql -X -q -o /dev/null -f spec/internal/db/structure.sql activerecord_views_test'
      raise unless $?.success?

      refreshed_ats = ActiveRecord::Base.connection.select_values("SELECT refreshed_at FROM active_record_views WHERE name = 'test_view'")
      expect(refreshed_ats).to eq [nil]
    end

    it 'does not write structure.sql when `schema_format = :ruby`', if: schema_rake_task != 'db:structure:dump' do
      rake schema_rake_task, env: {'SCHEMA_FORMAT' => 'ruby'}

      expect(File.exist?('spec/internal/db/schema.rb')).to eq true
      expect(File.exist?('spec/internal/db/structure.sql')).to eq false
    end
  end
end
