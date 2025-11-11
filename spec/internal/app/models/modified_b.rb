class ModifiedB < ActiveRecord::Base
  self.implicit_order_column = :new_name
  is_view "SELECT new_name FROM #{ModifiedA.table_name};", dependencies: [ModifiedA]
end
