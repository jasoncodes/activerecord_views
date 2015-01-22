class DependencyB < ActiveRecord::Base
  is_view "SELECT id FROM #{DependencyA.table_name};", dependencies: [DependencyA]
end
