class DependencyB < ActiveRecord::Base
  self.implicit_order_column = :id
  is_view "SELECT id FROM #{DependencyA.table_name};", dependencies: [DependencyA]
end
