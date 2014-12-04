# ActiveRecordViews

ActiveRecordViews makes it easy to create and update PostgreSQL database views for ActiveRecord models.

Advantages over creating views manually in migrations include:

* Automatic reloading in development mode.
  This avoids the need to to run `rake db:migrate:redo` after every change.

* Keeps view changes in a single SQL file instead of spread across multiple migration files.
  This allows changes to views to be easily reviewed with `git diff`.

## Installation

Add this line to your application's `Gemfile`:

```ruby
gem 'activerecord_views'
```

## Usage

app/models/account.rb:

```ruby
class Account < ActiveRecord::Base
  has_many :transactions

  has_one :account_balance
  delegate :balance, :to => :account_balance
end
```

app/models/transaction.rb:

```ruby
class Transaction < ActiveRecord::Base
  belongs_to :account
end
```

app/models/account_balance.rb:

```ruby
class AccountBalance < ActiveRecord::Base
  is_view

  belongs_to :account
end
```

app/models/account_balance.sql:

```sql
SELECT accounts.id AS account_id, coalesce(sum(transactions.amount), 0) AS balance
FROM accounts
LEFT JOIN transactions ON accounts.id = transactions.account_id
GROUP BY accounts.id
```

Example usage:

```ruby
p Account.first.balance

Account.includes(:account_balance).find_each do |account|
  p account.balance
end
```

## Pre-populating views in Rails development mode

Rails loads classes lazily in development mode by default.
This means ActiveRecordViews models will not initialize and create/update database views until the model classes are accessed.
If you're debugging in `psql` and want to ensure all views have been created, you can force Rails to load them by running the following in a `rails console`:

```ruby
Rails.application.eager_load!
```

## Handling renames/deletions

ActiveRecordViews tracks database views by their name. When an ActiveRecordViews model is renamed or deleted, there is no longer a link between the model and the associated database table. This means an orphan view will be left in the database.

In order to keep things tidy and to avoid accidentally referencing a stale view, you should remove the view and associated ActiveRecordViews metadata when renaming or deleting a model using ActiveRecordViews. This is best done with a database migration (use `rails generate migration`) containing the following:

```ruby
ActiveRecordViews.drop_view connection, 'account_balances'
```

### Usage outside of Rails

When included in a Ruby on Rails project, ActiveRecordViews will automatically detect `.sql` files alongside models in `app/models`.
Outside of Rails, you will have to tell ActiveRecordViews where to find associated `.sql` files for models:

```ruby
require 'active_record'
require 'active_record_views'
require 'pg'

ActiveRecordViews.sql_load_path << '.' # load .sql files from current directory
ActiveRecordViews.init!
ActiveRecord::Base.establish_connection 'postgresql:///example'

class Foo < ActiveRecord::Base
  is_view
end

p Foo.all
```

## License

MIT
