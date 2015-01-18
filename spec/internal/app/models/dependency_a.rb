class DependencyA < ActiveRecord::Base
  is_view 'SELECT 2 AS id;'
end
