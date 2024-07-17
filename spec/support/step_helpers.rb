# frozen_string_literal: true

module StepHelpers
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

      req.reject! do |m, a, _k, _|
        requests.any? { |m_2, a_2, _, _| m == m_2 && a == a_2 }
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

        it { is_expected.to be_not_found.or be_forbidden }
        it { is_expected.not_to have_body(including(gem.contents)) }
      end

      request(:get_quick_spec, full_name) do
        let(:gem) { @all_gems.reverse_each.find { _1.full_name == full_name } || raise("gem not found") }

        it { is_expected.to be_not_found.or be_forbidden }
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
              @upstream_output = Tempfile.create("upstream.out").path
              Bundler.with_original_env do
                @upstream = "http://localhost:4567"
                @pid = spawn(Gem.ruby, "-rbundler/setup", "lib/gem_server_conformance/server.rb", out: @upstream_output,
                                                                                                  err: @upstream_output)
                raise "failed to start server" unless @pid
              end
            end

            @all_gems = []
            retries = 150
            loop do
              set_time Time.utc(1990)
              break
            rescue Errno::ECONNREFUSED
              retries -= 1
              raise "Failed to boot gem_server_conformance/server in under 5 seconds" if retries.zero?

              sleep 0.1
            else
              break
            end
          end

          after(:all) do
            if @pid
              Process.kill "TERM", @pid
              Process.wait @pid
              expect($?).to be_success, "Upstream server failed #{$?.inspect}:\n\n#{File.read(@upstream_output)}"
            end
          ensure
            File.unlink @upstream_output if @upstream_output
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

            etags = step.last_responses.filter_map do |k, v|
              next unless k.first == :get_info
              next unless v.ok?

              [k[1], v.response["ETag"]]
            end.to_h

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

  module ClassMethods
    def all_requests
      @all_requests ||= []
    end

    def all_requests_indices
      @all_requests_indices ||= {}
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end
end
