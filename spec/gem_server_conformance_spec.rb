# frozen_string_literal: true

RSpec.describe GemServerConformance do
  before(:all) do
    Gem.configuration.verbose = false
    ENV["SOURCE_DATE_EPOCH"] = "0"
  end

  # it "fails" do
  #   expect(true).to eq(false)
  # rescue RSpec::Expectations::ExpectationNotMetError
  # end

  xit "passes old conformance" do
    pid = spawn({ "UPSTREAM" => "1" }, "ruby", "-rbundler/setup", "lib/gem_server_conformance/server.rb", out: $stdout,
                                                                                                          err: $stderr)
    sleep 1
    Bundler.with_unbundled_env do
      system({ "UPSTREAM" => "http://localhost:4567" }, "bin/conformance_runner",
             chdir: "/Users/segiddins/Development/github.com/rubygems/compact_index")
    end
    expect($?).to be_success
  ensure
    if pid
      Process.kill "TERM", pid
      Process.wait pid
    end
  end

  xit "builds a gem" do
    g = build_gem("conformance", "0.0.1") do |spec|
      spec.add_runtime_dependency "rack"
    end

    set_time(Time.utc(1990))
    rebuild_versions_list
    set_time(Time.utc(1990).+(60))

    last_response = push_gem(g)
    expect(last_response).to have_attributes(
      code: "200"
    )

    last_response = get_versions
    expect(last_response).to have_attributes(
      code: "200",
      body: eq(<<~VERSIONS)
        created_at: 1990-01-01T00:00:00Z
        ---
        conformance 0.0.1,0.0.1,0.0.1,0.0.1,0.0.1 68da06f4b6789a902d206c569f525c33
        conformance 0.0.1 ce101802e6df1d8849b4b73809e53573
        conformance 0.0.1 8e6bed5d9c37f1dad2ed104b855bdaf8
        conformance 0.0.1 ed6905b3a4ad77a2a6be86e133aa065d
      VERSIONS
    )
  end

  xcontext "conformance server" do
    attr_reader :server, :app

    include Rack::Test::Methods

    before(:all) do
      @server = GemServerConformance::Server.new
      @app = GemServerConformance::Server::Application.new(@server)
    end

    after(:all) do
      # pp server
    end

    before(:all) do
      post "/set_time", Time.utc(1990).iso8601, { "CONTENT_TYPE" => "text/plain" }
      expect(last_response).to be_ok
        .and match("Time set to 1990-01-01 00:00:00 UTC")
    end

    context "rebuilding empty versions list" do
      before(:all) do
        post "/rebuild_versions_list"
        expect(last_response).to be_ok
          .and match("Rebuilt versions list")
        post "/set_time", Time.utc(1990).+(60).iso8601, { "CONTENT_TYPE" => "text/plain" }
        expect(last_response).to be_ok
          .and match("Time set to 1990-01-01 00:01:00 UTC")
      end

      it "returns empty versions list" do
        get "/versions"
        expect(last_response).to be_ok
          .and match("created_at: 1990-01-01T00:00:00Z\n---\n")
      end

      it "returns empty names" do
        get "/names"
        expect(last_response).to be_ok
        expect(last_response.body).to eq("---\n\n")
      end

      context "after pushing a gem" do
        before(:all) do
          post "/api/v1/gems", File.binread("/Users/segiddins/.gem/ruby/3.3.3/cache/rspec-3.13.0.gem"),
               { "CONTENT_TYPE" => "application/octet-stream" }
          expect(last_response.status).to eq 200
          post "/set_time", Time.utc(1990).+((60 * 2)).iso8601, { "CONTENT_TYPE" => "text/plain" }
          expect(last_response).to be_ok
            .and match("Time set to 1990-01-01 00:02:00 UTC")
        end

        it "returns the pushed gem" do
          get "/gems/rspec-3.13.0.gem"
          expect(last_response).to be_ok
          expect(last_response.headers).to include(
            "Content-Type" => "application/octet-stream",
            "Content-Length" => "10752"
          )
        end

        it "returns the pushed gem's spec" do
          get "/quick/Marshal.4.8/rspec-3.13.0.gemspec.rz"
          expect(last_response).to be_ok
          expect(last_response.headers).to include(
            "Content-Length" => "518"
          )
        end

        it "returns /versions" do
          get "/versions"
          expect(last_response).to be_ok
          expect(last_response.body).to eq(<<~VERSIONS)
            created_at: 1990-01-01T00:00:00Z
            ---
            rspec 3.13.0 da9732844588bcc499dedd5a1416a65e
          VERSIONS
        end

        it "returns /names" do
          get "/names"
          expect(last_response).to be_ok
          expect(last_response.body).to eq("---\nrspec\n")
        end

        it "returns /info/rspec" do
          get "/info/rspec"
          expect(last_response).to be_ok
          expect(last_response.body).to eq(<<~INFO)
            ---
            3.13.0 rspec-core:~> 3.13.0,rspec-expectations:~> 3.13.0,rspec-mocks:~> 3.13.0|checksum:d490914ac1d5a5a64a0e1400c1d54ddd2a501324d703b8cfe83f458337bab993
          INFO
        end
      end
    end
  end

  class Step
    attr_reader :parent, :requests, :children, :last_responses, :blk

    def initialize(ctx, parent = nil, &blk)
      @ctx = ctx
      @parent = parent
      @requests = []
      @last_responses = {}
      @children = []
      @parent&.children&.<< self
      @blk = blk
      define! unless parent
    end

    def previous_requests
      return [] unless @parent

      req = @parent.requests + @parent.previous_requests
      req.uniq!

      req.reject! do |m, a, k, _|
        requests.any? { |m2, a2, _, _| m == m2 && a == a2 }
      end
      req
    end

    def then(message, before: nil, **kwargs, &blk)
      raise ArgumentError, "block required" unless blk
      raise ArgumentError, "message required" unless message
      raise "already has children" if @children.any?

      Step.new(@ctx.instance_eval { context(message, **kwargs) }, self).tap do |step|
        step.instance_variable_get(:@ctx).before(:all, &before) if before
        step.instance_eval(&blk)
        step.define!
      end
    end

    # class NullReporter
    #   def self.method_missing(...)
    #     pp(...)
    #   end

    #   def self.example_failed(ex)
    #     pp ex
    #     puts ex.display_exception.full_message
    #   end
    # end

    def request(method, *args, **kwargs, &blk)
      name = method.to_s
      name += "(#{args.map(&:inspect).join(", ")})" unless args.empty?
      name += " unchanged" if kwargs[:unchanged]
      step = self

      reset_examples = proc do |ctx|
        ctx.examples.each do |example|
          example.display_exception = nil
          example.metadata[:execution_result] = RSpec::Core::Example::ExecutionResult.new
        end
        ctx.children.each(&reset_examples)
      end

      @ctx.context "#{name} response", **kwargs do
        before(:all) do
          20.times do
            send(method, *args)
            step.last_responses[[method, *args]] = last_response

            reporter = RSpec::Core::NullReporter
            self.class.store_before_context_ivars(self)
            result_for_this_group = self.class.run_examples(reporter)
            results_for_descendants = self.class.ordering_strategy.order(self.class.children).map do |child|
              child.run(reporter)
            end.all?

            reset_examples[self.class]
            break if result_for_this_group && results_for_descendants

            sleep 0.1
          end
        end
        let(:parent_response) do
          step.parent.last_responses[[method, *args]]
        end
        alias_method :subject, :last_response
        instance_eval(&blk)
      end

      @requests << [method, args, kwargs, blk, self]
    end

    def pushed_gem(full_name)
      request(:get_gem, full_name) do
        let(:gem) { @all_gems.reverse_each.find { _1.full_name == full_name } || raise("gem not found") }
        it { is_expected.to be_ok }
        it { is_expected.to have_header("content-type").with_value("application/octet-stream") }
          .metadata[:content_type_header] = true
        it { is_expected.to have_content_length }
          .metadata[:content_length_header] = true
        it { is_expected.to have_body(eq(gem.contents)) }
      end

      request(:get_quick_spec, full_name) do
        let(:gem) { @all_gems.reverse_each.find { _1.full_name == full_name } || raise("gem not found") }

        it { is_expected.to be_ok }
        it { is_expected.to have_header("content-type").with_value("application/octet-stream") }
          .metadata[:content_type_header] = true
        it { is_expected.to have_content_length }
          .metadata[:content_length_header] = true
        it { is_expected.to unmarshal_as(gem.spec.tap(&:sanitize).tap(&:abbreviate)).inflate(true) }
      end
    end

    def yanked_gem(full_name)
      request(:get_gem, full_name) do
        let(:gem) { @all_gems.reverse_each.find { _1.full_name == full_name } || raise("gem not found") }

        it { is_expected.to be_not_found }
        it { is_expected.not_to have_body(including(gem.contents)) }
      end

      request(:get_quick_spec, full_name) do
        let(:gem) { @all_gems.reverse_each.find { _1.full_name == full_name } || raise("gem not found") }

        it { is_expected.to be_not_found }
      end
    end

    def define!
      step = self

      instance_eval(&step.blk) if step.blk

      if step.parent.nil?
        @ctx.instance_eval do
          attr_reader :upstream

          before(:all) do
            @upstream = ENV.fetch("UPSTREAM", nil)
            unless upstream
              Bundler.with_original_env do
                @upstream = "http://localhost:4567"
                @pid = spawn("ruby", "-rbundler/setup", "lib/gem_server_conformance/server.rb", out: "/dev/null",
                                                                                                err: "/dev/null")
                sleep 1
              end
            end
          end

          after(:all) do
            if @pid
              Process.kill "TERM", @pid
              Process.wait @pid
            end
          end

          before(:all) do
            @all_gems = []
            set_time Time.utc(1990)
          end
        end
      end

      step.previous_requests.each do |method, args, kwargs, blk, s|
        request(method, *args, unchanged: true, **kwargs) do
          let(:parent_response) do
            s.parent.last_responses[[method, *args]]
          end
          instance_eval(&blk)
          if kwargs[:compact_index]
            it "is expected to have the same etag" do
              is_expected.to have_header("ETag").with_value(step.parent.last_responses[[method,
                                                                                        *args]].response["ETag"])
            end
          end
        end
      end

      if requests.any?
        @ctx.context "/versions", compact_index: true do
          it "has matching etags" do
            expect(step.last_responses).to include([:get_versions])
            versions_response = step.last_responses[[:get_versions]]

            expected = versions_response.body.lines.to_h do |l|
              n, _, e = l.split
              [n, "\"#{e}\""]
            end
            expected.delete("---")
            expected.delete("created_at:")

            etags = step.last_responses.map do |k, v|
              next unless k.first == :get_info
              next unless v.ok?

              [k[1], v.response["ETag"]]
            end.compact.to_h

            expect(etags).to eq(expected)
          end
        end

        @ctx.context "all expected requests", compact_index: true do
          it "are tested" do
            expect(step.last_responses).to include([:get_versions])
            versions_response = step.last_responses[[:get_versions]]

            expected = versions_response.body.lines.flat_map do |l|
              next if l.start_with?("---")
              next if l.start_with?("created_at:")

              n, versions, = l.split
              versions.split(",").flat_map do |v|
                v.delete_prefix!("-")
                [
                  [:get_quick_spec, ["#{n}-#{v}"]],
                  [:get_gem, ["#{n}-#{v}"]]
                ]
              end << [:get_info, [n]]
            end
            expected.compact!
            expected.uniq!

            actual = step.requests.map { |m, a, _| [m, a] }

            missing = expected - actual

            expect(missing).to be_empty
          end
        end
      end

      children.each(&:define!)
    end
  end

  def self.all_requests
    @all_requests ||= []
  end

  def self.all_requests_indices
    @all_requests_indices ||= {}
  end

  # def self.step(*args, before:, **kwargs, &blk)
  #   Step.new(
  #     context(*args, **kwargs) do
  #       before(:all, &before)

  #       instance_eval(&blk)

  #       unless kwargs[:single_response]
  #         our_reqs = all_requests.slice(idx..)

  #         all_requests[0, idx].each do |a|
  #           k = a.first
  #           next if our_reqs&.any? { _1[0] == k }

  #           request(*k) do
  #             it "is expected to be unchanged" do
  #               is_expected.to eq(a.last)
  #             end
  #           end
  #         end
  #       end
  #     end
  #   )
  # end

  # def self.request(meth, *args, **kwargs, &blk)
  #   name = meth.to_s
  #   name += "(#{args.map(&:inspect).join(", ")})" unless args.empty?

  #   a = [[meth, *args], nil]
  #   all_requests << a
  #   context "#{name} response", single_response: true, **kwargs do
  #     before(:all) do
  #       send(meth, *args)
  #       a[-1] = last_response
  #     end
  #     alias_method :subject, :last_response
  #     instance_eval(&blk)
  #   end
  # end

  Step
    .new(context("with conformance runner"))
    .then "after rebuilding empty versions list", before: ->(_) { rebuild_versions_list } do
    request :get_versions do
      # it "has ivars set" do
      #   expect(instance_variables.to_h { [_1, instance_variable_get(_1)] }).to eq({})
      # end
      it { is_expected.to be_valid_compact_index_reponse }
      it {
        is_expected.to have_body(
          "created_at: 1990-01-01T00:00:00Z\n---\n"
        )
      }
    end

    request :get_names do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(eq("---\n\n")) }
    end

    request :get_specs do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([]) }
    end

    request :get_specs, :prerelease do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([]) }
    end

    request :get_specs, :latest do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([]) }
    end

    request :get_info, "missing" do
      it { is_expected.to be_not_found }
    end

    request :get_gem, "missing" do
      it { is_expected.to be_not_found }
    end

    request :get_quick_spec, "missing" do
      it { is_expected.to be_not_found }
    end
  end
  .then "after first push", before: lambda { |_|
                                      @gem_a_1_0_0 = build_gem("a", "1.0.0")
                                      push_gem(@gem_a_1_0_0, expected_to: be_ok)
                                    } do
    pushed_gem("a-1.0.0")

    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it {
        is_expected.to have_body(
          parent_response.body + "a 1.0.0 8761412e66a014fe80723e251d96be29\n"
        )
      }
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_ok }
      it { is_expected.to have_body(<<~INFO) }
        ---
        1.0.0 |checksum:2dfc054a348d36faae6e98e8c0222a76c07cfa0620b3c47acb154cb3d2de149b
      INFO
      it { is_expected.to have_header("content-type").with_value("text/plain; charset=utf-8") }
    end

    request :get_names, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(eq("---\na\n")) }
    end

    request :get_specs do
      it { is_expected.to be_ok, last_response.body }
      it { is_expected.to unmarshal_as([["a", Gem::Version.new("1.0.0"), "ruby"]]) }
    end

    request :get_specs, :prerelease do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([]) }
    end

    request :get_specs, :latest do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([["a", Gem::Version.new("1.0.0"), "ruby"]]) }
    end
  end
  .then "after yanking only gem", before: ->(_) { yank_gem(@gem_a_1_0_0, expected_to: be_ok) } do
    yanked_gem("a-1.0.0")

    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it {
        is_expected.to have_body(parent_response.body + "a -1.0.0 6105347ebb9825ac754615ca55ff3b0c\n")
      }
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(<<~INFO) }
        ---
      INFO
    end

    request :get_names, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(eq("---\n\n")) }
    end

    request :get_specs do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([]) }
    end

    request :get_specs, :prerelease do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([]) }
    end

    request :get_specs, :latest do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([]) }
    end
  end
  .then "after second push", before: lambda { |_|
                                       push_gem(@a_0_0_1 = build_gem("a", "0.0.1"), expected_to: be_ok)
                                       push_gem(@b_1_0_0_pre = build_gem("b", "1.0.0.pre") do |spec|
                                         spec.add_runtime_dependency "a", "< 1.0.0", ">= 0.1.0"
                                         spec.required_ruby_version = ">= 2.0"
                                         spec.required_rubygems_version = ">= 2.0"
                                       end, expected_to: be_ok)
                                     } do
    pushed_gem("a-0.0.1")
    pushed_gem("b-1.0.0.pre")

    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~BODY) }
        a 0.0.1 22428c91ad748146bec818307104ed33
        b 1.0.0.pre 688f5cdf79887aff5d87c86f36cfe063
      BODY
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~INFO) }
        0.0.1 |checksum:5e25d516b8c19c9d26ef95efad565c2097865a0d3dba5ef3fade650a2e690b35
      INFO
    end

    request :get_info, "b", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(<<~INFO) }
        ---
        1.0.0.pre a:< 1.0.0&>= 0.1.0|checksum:3f97419b7c35257f7aab3ae37521ab64ef8ec7646ef55b9f6a5e41d479bc128c,ruby:>= 2.0,rubygems:>= 2.0
      INFO
    end

    request :get_names, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(eq("---\na\nb\n")) }
    end

    request :get_specs do
      it { is_expected.to be_ok }
      it {
        is_expected.to unmarshal_as(
          [["a", Gem::Version.new("0.0.1"), "ruby"]]
          # ["b", Gem::Version.new("1.0.0.pre"), "ruby"]
        )
      }
    end

    request :get_specs, :prerelease do
      it { is_expected.to be_ok }
      it {
        is_expected.to unmarshal_as([
                                      ["b", Gem::Version.new("1.0.0.pre"), "ruby"]
                                    ])
      }
    end

    request :get_specs, :latest do
      it { is_expected.to be_ok }
      it {
        is_expected.to unmarshal_as([
                                      ["a", Gem::Version.new("0.0.1"), "ruby"]
                                    ])
      }
    end

    request :get_gem, "a-0.0.1" do
      it { is_expected.to be_ok }
      it { is_expected.to have_content_length }
        .metadata[:content_length_header] = true
      it { is_expected.to have_body(eq(@a_0_0_1.contents)) }
    end

    request :get_gem, "b-1.0.0.pre" do
      it { is_expected.to be_ok }
      it { is_expected.to have_content_length }
        .metadata[:content_length_header] = true
      it { is_expected.to have_body(eq(@b_1_0_0_pre.contents)) }
    end

    request :get_quick_spec, "a-0.0.1" do
      it { is_expected.to be_ok }
      it { is_expected.to have_content_length }
        .metadata[:content_length_header] = true
      it {
        is_expected.to unmarshal_as(Gem::Specification.new do |s|
                                      s.name = "a"
                                      s.version = Gem::Version.new("0.0.1")
                                      s.installed_by_version = Gem::Version.new("0")
                                      s.authors = ["Conformance"]
                                      s.date = Time.utc(2024, 7, 9)
                                      s.description = ""
                                      s.require_paths = ["lib"]
                                      s.rubygems_version = "3.5.11"
                                      s.specification_version = 4
                                      s.summary = "Conformance test"
                                    end).inflate(true)
      }
    end

    request :get_quick_spec, "b-1.0.0.pre" do
      it { is_expected.to be_ok }
      it { is_expected.to have_content_length }
        .metadata[:content_length_header] = true
      it {
        is_expected.to unmarshal_as(Gem::Specification.new do |s|
                                      s.name = "b"
                                      s.version = Gem::Version.new("1.0.0.pre")
                                      s.installed_by_version = Gem::Version.new("0")
                                      s.authors = ["Conformance"]
                                      s.date = Time.utc(2024, 7, 9)
                                      s.description = ""
                                      s.require_paths = ["lib"]
                                      s.rubygems_version = "3.5.11"
                                      s.specification_version = 4
                                      s.summary = "Conformance test"
                                      s.add_dependency "a", ">= 0.1.0", "< 1.0.0"
                                      s.required_ruby_version = ">= 2.0"
                                      s.required_rubygems_version = ">= 2.0"
                                    end).inflate(true)
      }
    end
  end
  .then "third push", before: lambda { |_|
                                push_gem(build_gem("a", "0.0.1") { |s| s.add_runtime_dependency "b", ">= 1.0.0" },
                                         expected_to: be_conflict)
                                @all_gems.pop
                                push_gem(@a_0_2_0 = build_gem("a", "0.2.0"), expected_to: be_ok)
                                push_gem(build_gem("a", "0.2.0", platform: "x86-mingw32"), expected_to: be_ok)
                                push_gem(build_gem("a", "0.2.0", platform: "java"), expected_to: be_ok)
                              } do
    pushed_gem("a-0.2.0")
    pushed_gem("a-0.2.0-x86-mingw32")
    pushed_gem("a-0.2.0-java")

    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~BODY) }
        a 0.2.0 7a7528379bbd1e0420ea7f1305ba526a
        a 0.2.0-x86-mingw32 17f9c2882d6f0a244f8bba2df1d14107
        a 0.2.0-java ca5c12bc8ba4457ada41c71bee282bfb
      BODY
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~INFO) }
        0.2.0 |checksum:a1753a0e8b6f0515a15e9cfa4ea143e36de235525f6f68c4ff45c4ae70be072f
        0.2.0-x86-mingw32 |checksum:e330e73d0dec030107c5656bbe89aecae738ba483471bf87f1bd943093fc9f27
        0.2.0-java |checksum:897332272ac159bf200a690dae5039df1e60355124848f2a6f889563311421f4
      INFO
    end

    request :get_specs do
      it { is_expected.to be_ok, last_response.body }
      it {
        is_expected.to unmarshal_as(
          Marshal.load(Zlib.gunzip(parent_response.body)) + [
            ["a", Gem::Version.new("0.2.0"), "x86-mingw32"],
            ["a", Gem::Version.new("0.2.0"), "ruby"],
            ["a", Gem::Version.new("0.2.0"), "java"]
          ]
        )
      }
    end

    request :get_specs, :latest do
      it { is_expected.to be_ok }
      it {
        is_expected.to unmarshal_as([
                                      ["a", Gem::Version.new("0.2.0"), "x86-mingw32"],
                                      ["a", Gem::Version.new("0.2.0"), "ruby"],
                                      ["a", Gem::Version.new("0.2.0"), "java"]
                                    ])
      }
    end

    request :get_specs, :prerelease do
      it { is_expected.to be_ok }
      it {
        is_expected.to unmarshal_as([
                                      ["b", Gem::Version.new("1.0.0.pre"), "ruby"]
                                    ])
      }
    end
  end
  .then "after rebuilding versions list", before: ->(_) { rebuild_versions_list } do
    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(<<~BODY) }
        created_at: 1990-01-01T01:08:00Z
        ---
        a 0.0.1,0.2.0,0.2.0-x86-mingw32,0.2.0-java ca5c12bc8ba4457ada41c71bee282bfb
        b 1.0.0.pre 688f5cdf79887aff5d87c86f36cfe063
      BODY
    end
  end
  .then "after fourth push", before: ->(_) { push_gem(build_gem("a", "0.3.0"), expected_to: be_ok) } do
    pushed_gem("a-0.3.0")

    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~BODY) }
        a 0.3.0 6263c53d5a23dfe0339a3ebae0fed8da
      BODY
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~INFO) }
        0.3.0 |checksum:40f19de3ce5c3fc5930fbc5dc3a08cd0b31572852d4885b37a19039bad7d9784
      INFO
    end

    request :get_specs do
      it {
        is_expected.to unmarshal_as(
          Marshal.load(Zlib.gunzip(parent_response.body)) +
          [["a", Gem::Version.new("0.3.0"), "ruby"]]
        )
      }
    end

    request :get_specs, :latest do
      it { is_expected.to be_ok }
      it {
        is_expected.to unmarshal_as([
                                      ["a", Gem::Version.new("0.2.0"), "x86-mingw32"],
                                      ["a", Gem::Version.new("0.2.0"), "java"],
                                      ["a", Gem::Version.new("0.3.0"), "ruby"]
                                    ])
      }
    end
  end
  .then "after yanking a gem", before: ->(_) { yank_gem(@a_0_2_0, expected_to: be_ok) } do
    yanked_gem("a-0.2.0")

    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + "a -0.2.0 1fdcc4d621638a6ba75d8ed88b09f97a\n") }
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it {
        is_expected.to have_body(parent_response.body.lines.tap do
                                   _1.delete("0.2.0 |checksum:a1753a0e8b6f0515a15e9cfa4ea143e36de235525f6f68c4ff45c4ae70be072f\n")
                                 end.join)
      }
    end

    request :get_specs do
      it { is_expected.to be_ok }
      it { is_expected.to have_content_length }
        .metadata[:content_length_header] = true
      it {
        is_expected.to unmarshal_as(
          Marshal.load(Zlib.gunzip(parent_response.body)).tap { _1.delete(["a", Gem::Version.new("0.2.0"), "ruby"]) }
        )
      }
    end
  end
  .then "after rebuilding versions list", before: ->(_) { rebuild_versions_list } do
    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(<<~VERSIONS) }
        created_at: 1990-01-01T02:10:00Z
        ---
        a 0.0.1,0.2.0-x86-mingw32,0.2.0-java,0.3.0 1fdcc4d621638a6ba75d8ed88b09f97a
        b 1.0.0.pre 688f5cdf79887aff5d87c86f36cfe063
      VERSIONS
    end
  end
  .then "after yanking a missing gem", before: lambda { |_|
                                                 yank_gem(RequestHelpers::MockGem.new(name: "missing", version: "1.0.0"),
                                                          expected_to: be_not_found)
                                               } do
  end
end
