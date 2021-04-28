module ActiveRecordViews
  class Railtie < ::Rails::Railtie
    initializer 'active_record_views' do |app|
      ActiveSupport.on_load :active_record do
        ActiveRecordViews.sql_load_path += Rails.application.config.paths['app/models'].to_a
        ActiveRecordViews.init!
        ActiveRecordViews::Extension.create_enabled = !Rails.env.production?
      end

      unless app.config.cache_classes
        if app.respond_to?(:reloader)
          app.reloader.before_class_unload do
            ActiveRecordViews.reload_stale_views!
          end
          app.executor.to_run do
            ActiveRecordViews.reload_stale_views!
          end
        else
          ActiveSupport.on_load :action_controller do
            ActionDispatch::Callbacks.before do
              ActiveRecordViews.reload_stale_views!
            end
          end
        end
      end
    end

    rake_tasks do
      load 'tasks/active_record_views.rake'
    end
  end
end
