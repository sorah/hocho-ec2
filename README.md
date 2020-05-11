# hocho-ec2: Host inventory for Amazon EC2

This is a [sorah/hocho](https://github.com/sorah/hocho) inventory provider plugin that retrieves EC2 instance information as host data.

## Installation

Add this line to your Gemfile:

```ruby
gem 'hocho-ec2'
```

## Usage

```yaml
# hocho.yml
inventory_providers:
  - ec2:
      ## AWS Region
      region: ap-northeast-1
      ## ec2:DescribeInstances API filters
      filters:
        - name: instance-state-name
          values: ['running']
      ## ERB Template for host.name. You can use `tag(instance, "NAME")` and `tag(vpc, "NAME")` helper.
      hostname_template: '<%= tag(instance, "Name") %>.<%= tag(vpc, "Name") %>.compute.nkmi.me'
      ## Template - Ruby script for host.properties.template. Expected to return an Array.
      runlist_template: '%w(site.rb entry_ec2.rb entry_ec2_role.rb)'
      ## Cache the result for specified duration.
      cache_path: tmp/hocho-ec2-cache.apne1.yml
      cache_duration: 3600

  ## You can add multiple instnaces of a provider to cover more regions:
  # - ec2:
  #     region: us-west-2
  #     ...
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sorah/hocho-ec2.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
