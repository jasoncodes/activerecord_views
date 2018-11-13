unless ActiveRecordViews::Extension.currently_migrating?
  class MissingFileTestModel < ActiveRecord::Base
    is_view
  end
end
