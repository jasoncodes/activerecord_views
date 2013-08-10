class HeredocTestModel < ActiveRecord::Base
  is_view <<-SQL
    SELECT 1 AS id, 'Here document'::text AS name;
  SQL
end
