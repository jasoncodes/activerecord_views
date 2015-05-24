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

## Example

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

## Dependencies

You can use an view model from another view model or within SQL blocks in your application code.
In order to ensure the model file is loaded (and thus the view is created), you should reference
the model class when you use the view rather than using the database table name directly:

```ruby
connection.select_values <<-SQL
  SELECT …
  FROM …
  INNER JOIN #{AccountBalance.table_name} … # use instead of account_balances
  …
SQL
```

Due to the importance of ensuring view models load in the correct order, ActiveRecordViews has
a safety check which will require you to specify the dependency explicitly if your view refers
to another view model:

```ruby
class AccountBalance < ActiveRecord::Base
  is_view
end

class AccountSummary < ActiveRecord::Base
  is_view dependencies: [AccountBalance]
end
```

## Materialized views

ActiveRecordViews has support for [PostgreSQL's materialized views](http://www.postgresql.org/docs/9.4/static/rules-materializedviews.html).
By default, views execute their query to calculate the output every time they are accessed.
Materialized views let you cache the output of views. This is useful for views which have expensive calculations. Your application can then trigger a refresh of the cached data as required.

To configure an ActiveRecordViews model as being materialized, pass the `materialized: true` option to `is_view`:

```ruby
class AccountBalance < ActiveRecord::Base
  is_view materialized: true
end
```

Materialized views are not initially populated upon creation as this could greatly slow down application startup.
An exception will be raised if you attempt to read from a view before it is populated.
You can test if a materialized view has been populated with the `view_populated?` class method and trigger a refresh with the `refresh_view!` class method:

```ruby
AccountBalance.view_populated? # => false
AccountBalance.refresh_view!
AccountBalance.view_populated? # => true
```

ActiveRecordViews records when a view was last refreshed. This is often useful for giving users an idea of how stale data. To retrieve this timestamp, call `.refreshed_at` on the model:

PostgreSQL 9.4 supports refreshing materialized views concurrently. This allows other processes to continue reading old cached data while the view is being updated. To use this feature you must have define a unique index on the materialized view:

```sql
class AccountBalance < ActiveRecord::Base
  is_view materialized: true, unique_columns: %w[account_id]
end
```

Note: If your view has a single column as the unique key, you can also tell ActiveRecord about it by adding `self.primary_key = :account_id` in your model file. This is required for features such as `.find` and `.find_each` to work.

Once you have defined the unique columns for the view, you can then use `concurrent: true` to force a concurrent refresh or `concurrent: :auto` to concurrently refresh when possible:

```ruby
AccountBalance.refresh_view! concurrent: :auto
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

Alternatively, all view models can be dropped with the following:

```ruby
ActiveRecordViews.drop_all_views connection
```

## Usage outside of Rails

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
