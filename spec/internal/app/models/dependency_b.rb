class DependencyB < ActiveRecord::Base
  is_view 'SELECT * FROM dependency_as;'
end
