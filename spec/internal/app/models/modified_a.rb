class ModifiedA < ActiveRecord::Base
  is_view 'SELECT 22 AS new_name;'
end
