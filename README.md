# SubstrateClient

This is a library of interfaces for communicating with Substrate nodes. It provides application developers the ability to query a node and interact with the Substrate chains using Ruby.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'substrate_client'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install substrate_client

## Usage

### Api list

```ruby
require "substrate_client"

client = SubstrateClient.new("wss://kusama-rpc.polkadot.io/")
puts client.method_list
```
The rpc api methods is dynamically generated, so the methods returned by this method can be called.

## TODO

- [x] ws wss request support
- [ ] http request support
- [x] generate storage key
- [x] call any apis substrate node supported with ruby's method missing function
- [ ] metadata caching

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/substrate_client. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the SubstrateClient project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/substrate_client/blob/master/CODE_OF_CONDUCT.md).
