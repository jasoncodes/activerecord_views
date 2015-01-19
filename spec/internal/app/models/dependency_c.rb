class DependencyC < ActiveRecord::Base
  is_view "SELECT id FROM #{DependencyB.table_name};"
end
