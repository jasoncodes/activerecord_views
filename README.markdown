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

### Usage outside of Rails

```ruby
require 'active_record'
require 'active_record_views'
ActiveRecordViews.sql_load_path << '.'
ActiveRecordViews.init!
```

## License

MIT
