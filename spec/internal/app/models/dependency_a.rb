class DependencyA < ActiveRecord::Base
  self.implicit_order_column = :id
  is_view 'SELECT 2 AS id;'
end
