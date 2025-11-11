class ErbTestModel < ActiveRecord::Base
  self.implicit_order_column = :id
  def self.test_erb_method
    'ERB method'
  end

  is_view
end
