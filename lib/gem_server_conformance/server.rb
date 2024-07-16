require "compact_index"
require "rubygems/package"
require "sinatra/base"

module GemServerConformance
  class Server
    class Application < Sinatra::Base
      Sinatra::ShowExceptions.class_eval do
        undef_method :prefers_plain_text?
        def prefers_plain_text?(_)
          true
        end
      end
      def initialize(server = Server.new)
        @server = server
        super()
      end

      set :lock, true
      set :raise_errors, true

      post "/api/v1/gems" do
        @server.push(request.body.read)
      end

      delete "/api/v1/gems/yank" do
        @server.yank(params["gem_name"], params["version"], params["platform"])
      end

      after(%r{/(?:names|versions|info/[^/]+)}) do
        headers "Content-Type" => "text/plain; charset=utf-8"
        break unless response.status == 200

        headers "Accept-Ranges" => "bytes"
        etag Digest::MD5.hexdigest(response.body.join)
        sha256 = Digest::SHA256.base64digest(response.body.join)
        headers "Digest" => "sha-256=#{sha256}", "Repr-Digest" => "sha-256=:#{sha256}:"
      end

      get "/versions" do
        @server.versions
      end

      get "/info/:name" do
        @server.info(params[:name])
      end

      get "/names" do
        @server.names
      end

      get "/quick/Marshal.4.8/:id.gemspec.rz" do
        @server.quick_spec(params[:id])
      end

      get "/specs.4.8.gz" do
        @server.specs_gz
      end

      get "/prerelease_specs.4.8.gz" do
        @server.specs_gz("prerelease")
      end

      get "/latest_specs.4.8.gz" do
        @server.specs_gz("latest")
      end

      get "/gems/:id.gem" do
        @server.gem(params[:id])
      end

      # This is not part of the Gemstash API, but is used to set the time for the server

      post "/set_time" do
        @server.set_time Time.iso8601(request.body.read)
      end

      post "/rebuild_versions_list" do
        @server.rebuild_versions_list
      end
    end

    Version = Struct.new(:rubygem_name, :number, :platform, :info_checksum, :indexed, :prerelease, :sha256, :yanked_at,
                         :yanked_info_checksum,
                         :pushed_at, :package,
                         :position, :latest)

    def initialize
      @log = []
      @versions = []
      @versions_tempfile = Tempfile.create("versions.list")
      @versions_file = CompactIndex::VersionsFile.new(@versions_tempfile.path)
      @time = Time.at(0).utc
    end

    def reorder_versions
      @versions.group_by(&:rubygem_name).each do |name, versions|
        numbers = versions.map(&:number).sort.reverse

        versions.each do |version|
          version.position = numbers.index(version.number)
          version.latest = false
        end

        versions.select(&:indexed).reject(&:prerelease).group_by(&:platform).transform_values do |platform_versions|
          platform_versions.max_by(&:number).latest = true
        end
      end
    end

    def push(gem)
      package = Gem::Package.new(StringIO.new(gem))
      log "Pushed #{package.spec.full_name}"
      if @versions.any? { |v| v.package.spec.full_name == package.spec.full_name }
        return [409, {}, ["Conflict: #{package.spec.full_name} already exists"]]
      end

      version = Version.new(package.spec.name, package.spec.version.to_s, package.spec.platform, nil,
                            true, package.spec.version.prerelease?, Digest::SHA256.hexdigest(gem), nil, nil, @time, package)
      @versions << version
      reorder_versions
      version.info_checksum = Digest::MD5.hexdigest(info(version.rubygem_name).last.join)

      [200, {}, [@log.last]]
    end

    def yank(name, version, platform)
      full_name = [name, version, platform].compact.-(["ruby"]).join("-")
      yank = @versions.find do |v|
        v.package.spec.full_name == full_name && v.indexed
      end
      return [404, {}, [""]] unless yank

      log "Yanked #{yank.package.spec.full_name}"

      yank.indexed = false
      reorder_versions
      yank.yanked_at = @time
      yank.yanked_info_checksum = Digest::MD5.hexdigest(info(yank.rubygem_name).last.join)

      [200, {}, [""]]
    end

    def set_time(time) # rubocop:disable Naming/AccessorMethodName
      @time = time
      log "Time set to #{time}"
      [200, {}, [@log.last]]
    end

    def rebuild_versions_list
      gems = compact_index_gem_versions(separate_yanks: true,
                                        before: @time).group_by(&:name).transform_values do |gems_with_name|
               versions = gems_with_name.flat_map(&:versions)
               info_checksum = versions.last.info_checksum
               versions.reject! { _1.number.start_with?("-") }
               versions.each { |version| version.info_checksum = info_checksum }
             end.map do |name, versions|
        CompactIndex::Gem.new(name, versions)
      end.sort_by(&:name)
      @versions_file.create(gems, @time.iso8601)
      @log << "Rebuilt versions list"
      [200, {}, [@log.last]]
    end

    def versions
      [200, {},
       # calculate_info_checksums: true breaks with yanks
       [@versions_file.contents(compact_index_gem_versions(separate_yanks: true, after: @versions_file.updated_at.to_time))]]
    end

    def info(name)
      versions = compact_index_gem_versions
                 .select { _1.name == name }
                 .flat_map(&:versions)
      if versions.empty?
        return [404, { "Content-Type" => "text/plain; charset=utf-8" },
                ["This gem could not be found"]]
      end

      versions.reject! { _1.number.start_with?("-") }

      [200, {}, [CompactIndex.info(versions)]]
    end

    def names
      names = @versions.select(&:indexed).map!(&:rubygem_name).tap(&:sort!).tap(&:uniq!)
      [200, {}, [CompactIndex.names(names)]]
    end

    class Asc
      def initialize(obj)
        @obj = obj
      end

      attr_reader :obj
      protected :obj

      def <=>(other)
        return other.obj <=> obj if other.is_a?(self.class)

        other <=> obj
      end
    end

    def specs_gz(name = nil)
      case name
      when nil
        specs = @versions.select(&:indexed).reject(&:prerelease)
      when "latest"
        specs = @versions.select(&:indexed).select(&:latest)
      when "prerelease"
        specs = @versions.select(&:indexed).select(&:prerelease)
      else
        return [404, { "Content-Type" => "text/plain" }, ["File not found: /specs.4.8.gz\n"]]
      end

      specs.sort_by! do |v|
        [v.rubygem_name, Asc.new(v.position), Asc.new(v.platform.to_s)]
      end
      specs.map! do |v|
        [v.rubygem_name, Gem::Version.new(v.number), v.platform.to_s]
      end

      [200, { "Content-Type" => "application/octet-stream" }, [Zlib.gzip(Marshal.dump(specs))]]
    end

    def quick_spec(original_name)
      version = @versions.find do |v|
        v.indexed && v.package.spec.original_name == original_name
      end

      if version
        spec = version.package.spec.dup
        spec.abbreviate
        spec.sanitize
        # TODO
        if ENV["UPSTREAM"]
          [200, { "Content-Type" => "text/plain" }, [Gem.deflate(Marshal.dump(spec))]]
        else
          [200, { "Content-Type" => "application/octet-stream" }, [Gem.deflate(Marshal.dump(spec))]]
        end
      else
        [404, { "Content-Type" => "text/plain" }, ["File not found: /quick/Marshal.4.8/#{original_name}.gemspec.rz\n"]]
      end
    end

    def gem(full_name)
      version = @versions.find do |v|
        v.indexed && v.package.spec.full_name == full_name
      end

      if version
        contents = version.package.gem.io.string
        [200, { "Content-Type" => "application/octet-stream" }, [contents]]
      else
        [404, { "Content-Type" => "text/plain" }, ["File not found: /gems/#{full_name}.gem\n"]]
      end
    end

    private

    def log(message)
      @log << "[#{@time}] #{message}"
      # warn @log.last
    end

    def compact_index_gem_versions(separate_yanks: false, before: nil, after: nil)
      raise ArgumentError, "before and after cannot be used together" if before && after

      if separate_yanks
        yanks = @versions.select(&:yanked_at)
        yanks.select! { _1.yanked_at > after } if after
        yanks.reject! { _1.yanked_at <= before } if before

        yanks.map! do |version|
          version = version.dup
          version.indexed = true
          version.yanked_at = nil
          version.yanked_info_checksum = nil
          version
        end
      else
        yanks = []
      end

      all_versions = @versions + yanks
      all_versions.select! { (_1.yanked_at || _1.pushed_at) <= before } if before
      all_versions.select! { _1.pushed_at > after || (_1.yanked_at && _1.yanked_at > after) } if after

      all_versions
        # use index to keep order stable
        .sort_by.with_index { |version, idx| [version.yanked_at || version.pushed_at, idx] }
        .map do |version|
        spec = version.package.spec
        CompactIndex::Gem.new(
          version.rubygem_name,
          [
            CompactIndex::GemVersion.new(
              version.number.then do |n|
                version.indexed ? n : "-#{n}"
              end,
              version.platform,
              version.sha256,
              version.yanked_info_checksum || version.info_checksum,
              spec.runtime_dependencies.map do |dep|
                CompactIndex::Dependency.new(dep.name, dep.requirement.to_s)
              end,
              spec.required_ruby_version&.to_s, spec.required_rubygems_version&.to_s
            )
          ]
        )
      end
    end
  end
end

if __FILE__ == $0
  require "rackup"
  GemServerConformance::Server::Application.run!
end
