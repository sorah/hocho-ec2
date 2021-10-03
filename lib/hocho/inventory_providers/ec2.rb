require 'hocho/inventory_providers/base'
require 'hocho/host'
require 'yaml'
require 'erb'

require 'aws-sdk-ec2'

module Hocho
  module InventoryProviders
    class Ec2 < Base
      CACHE_PERMITTED_CLASSES = [
        TrueClass,
        FalseClass,
        NilClass,
        Integer,
        Float,
        String,
        Array,
        Hash,
        Time,
        Symbol,
        Aws::EC2::Types::IamInstanceProfile,
      ]

      module TemplateHelper
        def tag(source, name, default = nil)
          t = source.tags.find{ |_| _.key == name }
          t ? t.value : default
        end
      end

      RunlistTemplate = Struct.new(:instance, :vpc) do
        include TemplateHelper
      end
      class HostnameTemplate
        def self.erb; @erb; end
        def self.erb=(x); @erb = x; end

        include TemplateHelper

        def initialize(instance, vpc)
          @instance = instance
          @vpc = vpc
        end

        attr_reader :instance, :vpc

        def result()
          self.class.erb.result(binding)
        end
      end

      def initialize(region:, filters: nil, hostname_template: "<%= instance.private_dns_name %>", runlist_template: nil, cache_path: nil, cache_duration: 3600, cache_version: nil)
        @region = region
        @filters = filters
        @cache_path = cache_path
        @cache_duration = cache_duration&.to_i
        @cache_version = cache_version
        @hostname_template = Class.new(HostnameTemplate) do |c|
          c.erb = ERB.new(hostname_template, trim_mode: '-')
        end
        @runlist_template = eval("Class.new(RunlistTemplate){ def result; #{runlist_template}\nend; }")
      end

      attr_reader :region, :filters, :cache_path, :cache_duration, :cache_version, :hostname_template, :runlist_template

      def ec2
        @ec2 ||= Aws::EC2::Client.new(region: region)
      end

      def fetch_hosts
        vpcs = ec2.describe_vpcs().flat_map do |page|
          page.vpcs.map do |vpc|
            [vpc.vpc_id, vpc]
          end
        end.to_h
        subnets= ec2.describe_subnets().flat_map do |page|
          page.subnets.map do |subnet|
            [subnet.subnet_id, subnet]
          end
        end.to_h
        ec2.describe_instances(filters: filters).flat_map do |page|
          page.reservations.flat_map do |reservation|
            reservation.instances.map do |instance|
              next if instance.state.name == 'terminated' || instance.state.name == 'terminating'
              vpc = vpcs[instance.vpc_id]
              subnet = subnets[instance.subnet_id]
              fetch_instance(instance, vpc, subnet)
            end.compact
          end
        end
      end

      def cache_enabled?
        @cache_path && @cache_duration
      end

      def cache!
        return yield unless cache_enabled?
        if ::File.exist?(cache_path)
          @cache = YAML.load_file(cache_path, permitted_classes: CACHE_PERMITTED_CLASSES)
        end
        @cache = nil if !@cache&.key?(:ts) || (Time.now - @cache[:ts]) > cache_duration
        @cache = nil if cache_version && @cache[:user_version] != cache_version

        unless @cache
          @cache = {ts: Time.now, user_version: cache_version, content: yield}
          FileUtils.mkdir_p ::File.dirname(cache_path)
          ::File.write cache_path, YAML.dump(@cache)
        end
        @cache[:content]
      end

      def hosts
        @hosts ||= cache! { fetch_hosts }.map do |host_data|
          Host.new(
            host_data.fetch(:name),
            providers: self.class,
            properties: host_data[:properties],
            tags: host_data[:tags],
            ssh_options: host_data[:ssh_options],
          )
        end
      end

      private

      def fetch_instance(instance, vpc, subnet)
        tags = {
          'ec2.instance-id' => instance.instance_id,
          'ec2.iam-instance-profile' => instance.iam_instance_profile,
          'ec2.vpc-id' => instance.vpc_id,
          'ec2.subnet-id' => instance.subnet_id,
        }
        {'vpc-tags' => vpc.tags, 'tags' => instance.tags}.each do |prefix, aws_tags|
          aws_tags.each do |tag|
            tags["ec2.#{prefix}.#{tag.key.downcase}"] = tag.value
          end
        end

        ec2_attribute = instance.to_h
        vpc_attribute = vpc.to_h
        subnet_attribute = subnet.to_h
        [ec2_attribute, vpc_attribute, subnet_attribute].each do |attrs|
          attrs[:tags] = attrs.fetch(:tags, []).map { |_| [_.fetch(:key), _.fetch(:value)] }.to_h
        end

        properties = {
          run_list: runlist_template.new(instance, vpc).result(),
          attributes: {hocho_ec2: ec2_attribute, hocho_vpc: vpc_attribute, hocho_subnet: subnet_attribute,},
        }
        {
          name: hostname_template.new(instance, vpc).result(),
          properties: properties,
          tags: tags,
        }
      end

    end
  end
end
