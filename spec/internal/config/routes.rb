Rails.application.routes.draw do
  root to: -> (env) { [204, {}, []] }
end
