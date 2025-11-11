class Namespace::TestModel < ActiveRecord::Base
  self.implicit_order_column = :id
  is_view
end
