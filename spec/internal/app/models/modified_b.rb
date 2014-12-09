class ModifiedB < ActiveRecord::Base
  is_view "SELECT new_name FROM #{ModifiedA.table_name};"
end
