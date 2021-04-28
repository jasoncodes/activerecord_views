class ErbTestModel < ActiveRecord::Base
  def self.test_erb_method
    'ERB method'
  end

  is_view
end
