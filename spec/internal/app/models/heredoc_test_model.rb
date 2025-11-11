class HeredocTestModel < ActiveRecord::Base
  self.implicit_order_column = :id
  is_view <<-SQL
    SELECT 1 AS id, 'Here document'::text AS name;
  SQL
end
