# frozen_string_literal: true

require "rubygems/gemcutter_utilities"

module RequestHelpers
  def self.included(base)
    super
    base.attr_reader :last_response
  end

  module SpecificationToYamlNormalization
    class CoderWrapper < SimpleDelegator
      def add(key, value)
        value = "3.5.11" if key == "rubygems_version"
        return if value.nil?

        super
      end
    end

    def encode_with(coder)
      super(CoderWrapper.new(coder))
    end
  end

  module PackageGzipToConsistentOS
    class IOWrapper < SimpleDelegator
      def write(str)
        str[9] = "\x03".b if str.size == 10 && str.start_with?("\x1f\x8b".b)
        super
      end
    end

    def gzip_to(io, &blk)
      super(IOWrapper.new(io), &blk)
    end
  end

  ::Gem::Dependency.class_eval do
    if Gem::Dependency.method_defined?(:to_yaml_properties)
      prepend(
        Module.new do
          def to_yaml_properties
            expected = %i[@name @requirement @type @prerelease @version_requirements]
            actual = super

            (expected & actual) + (actual - expected)
          end
        end
      )
    end
  end

  def build_gem(name, version, platform: nil)
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.authors = ["Conformance"]
      s.summary = "Conformance test"
      s.files = []
      s.date = "2024-07-09"
      s.platform = platform if platform
    end
    yield spec if block_given?

    spec.singleton_class.prepend(SpecificationToYamlNormalization) if Gem.rubygems_version < Gem::Version.new("3.6.0")

    package = Gem::Package.new(StringIO.new.binmode)
    package.build_time = Time.utc(1970)
    package.spec = spec
    package.singleton_class.prepend(PackageGzipToConsistentOS)
    package.gem.singleton_class.send(:define_method, :path) { "" }

    package.build

    if ENV["DUMP_BUILD_GEM"]
      tmp = "build_gem/#{RUBY_ENGINE}/rubygems-#{Gem::VERSION}/#{@time}"
      FileUtils.mkdir_p(tmp)
      File.binwrite("#{tmp}/#{spec.full_name}.gem", package.gem.io.string)
    end

    MockGem.new(
      name: name,
      version: spec.version,
      platform: spec.platform,
      sha256: Digest::SHA256.hexdigest(package.gem.io.string),
      contents: package.gem.io.string
    ).tap { @all_gems << _1 }
  end

  MockGem = Struct.new(:name, :version, :platform, :sha256, :contents, keyword_init: true) do
    def full_name
      if platform == "ruby"
        "#{name}-#{version}"
      else
        "#{name}-#{version}-#{platform}"
      end
    end

    def prerelease?
      version.prerelease?
    end

    def size
      contents.bytesize
    end

    def spec
      io = StringIO.new(contents)
      io.binmode
      Gem::Package.new(io).spec
    end

    def pretty_print(pp)
      pp.object_address_group(self) do
        attr_names = %i[name version platform sha256 size]
        pp.seplist(attr_names, proc { pp.text "," }) do |attr_name|
          pp.breakable " "
          pp.group(1) do
            pp.text attr_name
            pp.text ":"
            pp.breakable
            value = send(attr_name)
            pp.pp value
          end
        end
      end
    end
  end

  module Pusher
    extend Gem::GemcutterUtilities

    def self.options
      {}
    end
  end

  def push_gem(gem, expected_to:)
    rubygems_api_request(
      :post,
      "api/v1/gems",
      upstream,
      scope: :push_rubygem
    ) do |request|
      request.body = gem.contents
      request["Content-Length"] = gem.size.to_s
      request["Content-Type"] = "application/octet-stream"
      request.add_field "Authorization", Pusher.api_key
    end.tap do
      expect(last_response).to expected_to, last_response.body
      set_time @time + 60
    end
  end

  def yank_gem(gem, expected_to:)
    rubygems_api_request(
      :delete,
      "api/v1/gems/yank",
      upstream,
      scope: :yank_rubygem
    ) do |request|
      request.body = URI.encode_www_form(
        gem_name: gem.name,
        version: gem.version.to_s,
        platform: gem.platform
      )
      request["Content-Length"] = request.body.bytesize.to_s
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.add_field "Authorization", Pusher.api_key
    end.tap do
      expect(last_response).to expected_to, last_response.body
      set_time @time + 60
    end
  end

  def set_time(time) # rubocop:disable Naming/AccessorMethodName
    @time = time
    body = time.iso8601
    rubygems_api_request(
      :post,
      "set_time",
      upstream
    ) do |request|
      request.body = body
      request["Content-Length"] = body.to_s
      request["Content-Type"] = "text/plain"
    end.tap do |response|
      expect(response.code).to eq "200"
    end
  end

  def rebuild_versions_list
    rubygems_api_request(
      :post,
      "rebuild_versions_list",
      upstream
    ) { nil }.tap do |response|
      expect(response.code).to eq "200"
      set_time @time + 3600
    end
  end

  def get_versions # rubocop:disable Naming/AccessorMethodName
    rubygems_api_request(
      :get,
      "versions",
      upstream
    ) { nil }
  end

  def get_names # rubocop:disable Naming/AccessorMethodName
    rubygems_api_request(
      :get,
      "names",
      upstream
    ) { nil }
  end

  def get_info(name)
    rubygems_api_request(
      :get,
      "info/#{name}",
      upstream
    ) { nil }
  end

  def get_gem(name)
    rubygems_api_request(
      :get,
      "gems/#{name}.gem",
      upstream
    ) { nil }
  end

  def get_quick_spec(name)
    rubygems_api_request(
      :get,
      "quick/Marshal.4.8/#{name}.gemspec.rz",
      upstream
    ) { nil }
  end

  def get_specs(name = nil)
    path = [name, "specs.4.8.gz"].compact.join("_")
    rubygems_api_request(
      :get,
      path,
      upstream
    ) { nil }
  end

  class MockResponse
    attr_reader :response

    def initialize(response)
      @response = response
    end

    def inspect
      headers = +"HTTP/#{response.http_version} #{response.code} #{response.message}\n".b
      response.each_header do |name, value|
        headers << "#{name}: #{value}\n"
      end
      headers << "\n"
      headers << response.body
    end

    def ok?
      response.code == "200"
    end

    def not_found?
      response.code == "404"
    end

    def conflict?
      response.code == "409"
    end

    def forbidden?
      response.code == "403"
    end

    def ==(other)
      return false unless other.is_a?(self.class)

      response.to_hash == other.response.to_hash &&
        response.body == other.response.body
    end

    extend Forwardable

    def_delegators :response, :code, :body, :http_version
    def_delegators "response.body", :match?, :===, :=~
  end

  def rubygems_api_request(...)
    internal = internal_request?(...)
    Pusher.rubygems_api_request(...).tap do |response|
      @last_response = MockResponse.new(response) unless internal
    end
  end

  def internal_request?(_, path, *, **)
    case path
    when "rebuild_versions_list", "set_time"
      true
    else
      false
    end
  end

  RSpec::Matchers.define :have_header do
    match do |response|
      expect(response).to be_a(MockResponse)

      @header_value = response.response.fetch(expected, nil)
      values_match?(@value, @header_value)
    end

    failure_message do |_response|
      super() + ", but got: #{description_of(@header_value)}"
    end

    chain :with_value do |value|
      @value = value
    end
  end

  RSpec::Matchers.define :have_body do
    match do |response|
      expect(response).to be_a(MockResponse)
      body = response.body.b
      @actual = body
      values_match?(expected, body)
    end

    diffable
  end

  RSpec::Matchers.define :encoded_as do
    match do |str|
      @actual = str.encoding.to_s
      expect(str.encoding).to eq(expected)
    end
    diffable
  end

  RSpec::Matchers.define :be_valid_compact_index_reponse do
    match notify_expectation_failures: true do |response|
      expect(response).to be_a(MockResponse)
        .and be_ok
        .and have_header("content-type").with_value("text/plain; charset=utf-8")
        .and have_header("accept-ranges").with_value("bytes")
        .and have_header("digest").with_value("sha-256=#{Digest::SHA256.base64digest(response.body)}")
        .and have_header("repr-digest").with_value("sha-256=:#{Digest::SHA256.base64digest(response.body)}:")
        .and have_header("etag").with_value("\"#{Digest::MD5.hexdigest(response.body)}\"")
    end
  end

  RSpec::Matchers.define :have_content_length do
    match do |response|
      expect(response).to be_a(MockResponse)
      expect(response).to have_header("content-length").with_value(response.body.bytesize.to_s)
    end
  end

  RSpec::Matchers.define :be_unchanged do
    match do |response|
      expect(response).to be_a(MockResponse)
      expect(response).to be_not_found
    end
  end

  RSpec::Matchers.define :unmarshal_as do
    match do |response|
      expect(response).to be_a(MockResponse)
      body = response.body.b
      body = if must_inflate
               Zlib.inflate(body)
             else
               Zlib.gunzip(body)
             end
      @actual = Marshal.load(body)
      values_match?(expected, @actual)
    end

    chain :inflate, :must_inflate

    diffable
  end
end
