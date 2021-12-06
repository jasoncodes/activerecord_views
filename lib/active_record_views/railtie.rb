module ActiveRecordViews
  class Railtie < ::Rails::Railtie
    initializer 'active_record_views' do |app|
      ActiveSupport.on_load :active_record do
        ActiveRecordViews.sql_load_path += Rails.application.config.paths['app/models'].to_a
        ActiveRecordViews.init!
        ActiveRecordViews::Extension.create_enabled = !Rails.env.production?
      end

      unless app.config.cache_classes
        app.reloader.before_class_unload do
          ActiveRecordViews.reload_stale_views!
        end
        app.executor.to_run do
          ActiveRecordViews.reload_stale_views!
        end
      end
    end

    rake_tasks do
      load 'tasks/active_record_views.rake'
    end
  end
end
