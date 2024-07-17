# GemServerConformance

A conformance test suite for RubyGems servers.

## Usage

Run `gem_server_conformance` to run the test suite against a server. The endpoint to test can be specified with the `UPSTREAM` environment variable. Make sure to set the `GEM_HOST_API_KEY` environment variable to an API key with push/yank permissions if authentication is required.

In addition to the standard interface,
you will also need to define the following endpoints:

- `POST /set_time` - Set the server's time to the value of the body's iso8601 value.
- `POST /rebuild_versions_list` - Rebuild the base /versions file.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rubygems/gem_server_conformance.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
