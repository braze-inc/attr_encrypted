# BrazeSentry

Wrapper around <https://sentry.io/> error tracking, and around upstream gems `sentry-ruby, sentry-rails, sentry-sidekiq`.

This ruby gem gets uploaded to our VPN-accessible Artifactory instance, and can be used in a ruby project with:

```ruby
source "https://artifactory.infra.braze.com/artifactory/api/gems/braze-gems-local" do
  gem 'braze_sentry'
end
```

## Usage

**BrazeSentry::Adapter** provides safe access to sentry-ruby's `capture_exception` and `capture_message` via `with_rescued_exceptions`, see [adapter\_spec.rb](spec/braze_sentry/adapter_spec.rb).

**BrazeSentry::Teams** defines a list of engineering teams that are mapped in the sentry.io UI to teams to make assigning ownership to sentry alerts automatic.

**BrazeSentry::Sidekiq::ErrorHandler** replaces upstream `Sentry::Sidekiq::ErrorHandler`, see [error\_handler\_spec.rb](spec/braze_sentry/sidekiq/error_handler_spec.rb).

## Development

Install dependencies with `bundle install`, the version of ruby and bundler should match what is used in <https://github.com/appboy/platform>.

### Tests

Run `bundle exec rspec`

### Rubocop formatting

Run `bundle exec rubocop`
