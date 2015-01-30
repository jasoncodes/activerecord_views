require 'database_cleaner/active_record/truncation'

module ActiveRecordViews
  module DatabaseCleaner
    module TruncationExtension
      def migration_storage_names
        super + %w[active_record_views]
      end
    end
  end
end

::DatabaseCleaner::ActiveRecord::Truncation.prepend ActiveRecordViews::DatabaseCleaner::TruncationExtension
