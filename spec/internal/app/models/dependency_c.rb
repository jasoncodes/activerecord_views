class DependencyC < ActiveRecord::Base
  is_view "SELECT id FROM #{DependencyB.table_name};", dependencies: [DependencyB]
end
