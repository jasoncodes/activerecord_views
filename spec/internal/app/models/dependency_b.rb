class DependencyB < ActiveRecord::Base
  is_view "SELECT * FROM #{DependencyA.table_name};"
end
