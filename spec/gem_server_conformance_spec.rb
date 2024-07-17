# frozen_string_literal: true

require_relative "support/step_helpers"

RSpec.describe GemServerConformance do # rubocop:disable RSpec/EmptyExampleGroup
  include StepHelpers

  before(:all) do
    Gem.configuration.verbose = false
    Gem::DefaultUserInteraction.ui = Gem::SilentUI.new
    ENV["SOURCE_DATE_EPOCH"] = "0"
  end

  StepHelpers::Step
    .new(context("with conformance runner"))
    .then "after rebuilding empty versions list", before: ->(_) { rebuild_versions_list } do
    request :get_versions do
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

    @ctx.it "has the exact contents as expected" do
      allow(RSpec::Support::ObjectFormatter.default_instance).to receive(:prepare_for_inspection).and_call_original
      allow(RSpec::Support::ObjectFormatter.default_instance)
        .to receive(:prepare_for_inspection).with(an_instance_of(String)) { |s| s }
      io = StringIO.new(@gem_a_1_0_0.contents)
      io.binmode
      package = Gem::Package.new(io)
      actual = []
      dump_tar = proc do |tar_io, into = actual|
        Gem::Package::TarReader.new(tar_io) do |gem|
          gem.each do |entry|
            body = entry.read
            body = Zlib.gunzip(body) if entry.full_name.end_with?(".gz")
            body = dump_tar[StringIO.new(body), []] if entry.full_name.end_with?(".tar.gz")

            into << {
              header: entry.header.instance_variables.to_h do |ivar|
                        [ivar.to_s.tr("@", "").to_sym, entry.header.instance_variable_get(ivar)]
                      end,
              body: body
            }
          end
        end
        into
      end
      package.gem.with_read_io(&dump_tar)
      expect(actual).to eq(
        [{ body: <<~YAML,
          --- !ruby/object:Gem::Specification
          name: a
          version: !ruby/object:Gem::Version
            version: 1.0.0
          platform: ruby
          authors:
          - Conformance
          bindir: bin
          cert_chain: []
          date: 2024-07-09 00:00:00.000000000 Z
          dependencies: []
          executables: []
          extensions: []
          extra_rdoc_files: []
          files: []
          licenses: []
          metadata: {}
          rdoc_options: []
          require_paths:
          - lib
          required_ruby_version: !ruby/object:Gem::Requirement
            requirements:
            - - ">="
              - !ruby/object:Gem::Version
                version: '0'
          required_rubygems_version: !ruby/object:Gem::Requirement
            requirements:
            - - ">="
              - !ruby/object:Gem::Version
                version: '0'
          requirements: []
          rubygems_version: 3.5.11
          specification_version: 4
          summary: Conformance test
          test_files: []
        YAML
           header: { checksum: 5894,
                     devmajor: 0,
                     devminor: 0,
                     empty: false,
                     gid: 0,
                     gname: "wheel",
                     linkname: "",
                     magic: "ustar",
                     mode: 292,
                     mtime: 0,
                     name: "metadata.gz",
                     prefix: "",
                     size: 318,
                     typeflag: "0",
                     uid: 0,
                     uname: "wheel",
                     version: 0 } },
         { body: [],
           header: { checksum: 5834,
                     devmajor: 0,
                     devminor: 0,
                     empty: false,
                     gid: 0,
                     gname: "wheel",
                     linkname: "",
                     magic: "ustar",
                     mode: 292,
                     mtime: 0,
                     name: "data.tar.gz",
                     prefix: "",
                     size: 35,
                     typeflag: "0",
                     uid: 0,
                     uname: "wheel",
                     version: 0 } },
         { body: <<~YAML,
           ---
           SHA256:
             metadata.gz: 5a1eb70f836c830856bd6ff54ae48916e6f5f297608012575884131c74089b36
             data.tar.gz: 6578c1623326a8b876f84c946634f7208ce54f23a75fa5775b44469ddb08a8e7
           SHA512:
             metadata.gz: 26dbf51d174890d592f13c0bccc6638e02e34f603684e9df7320508f777bf9da5061dd13f8262eef47ddcc0d975e33a9eead945de9544bbb4fd9358cfda0f026
             data.tar.gz: ea28bfbb44a5ca539ed7b50c492c0a5aa6cce60f7babad5c65cb2aca5c100ac350fb28eeb1c4ae32c8cf22c2724595b946e1cb12f521eeaf0a7246a26aad00a0
         YAML
           header: { checksum: 6506,
                     devmajor: 0,
                     devminor: 0,
                     empty: false,
                     gid: 0,
                     gname: "wheel",
                     linkname: "",
                     magic: "ustar",
                     mode: 292,
                     mtime: 0,
                     name: "checksums.yaml.gz",
                     prefix: "",
                     size: 295,
                     typeflag: "0",
                     uid: 0,
                     uname: "wheel",
                     version: 0 } }]
      )
    end

    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }

      it {
        is_expected.to have_body(
          parent_response.body + "a 1.0.0 443730449deef440bd299e19554793f0\n"
        )
      }
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_ok }
      it { is_expected.to have_body(<<~INFO) }
        ---
        1.0.0 |checksum:9bc2cb93a200173fcd556c6c674bb4cdbce9b284e5dea0be9c21ee801f38b821
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
        a 0.0.1 8ffe0a0dda27362c6f916d3941a5726e
        b 1.0.0.pre f0d229a9323895e2e1c85f496b5f10b5
      BODY
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~INFO) }
        0.0.1 |checksum:a2bee9c1c6b2ab54a19c4d4644663eda25c2326bebe0eb9f9c097a2a11fd6203
      INFO
    end

    request :get_info, "b", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(<<~INFO) }
        ---
        1.0.0.pre a:< 1.0.0&>= 0.1.0|checksum:4096fbca288dcf4b4cea8bbebdea5d10d6b3f4fd2ff3c13124852854d5d7d24b,ruby:>= 2.0,rubygems:>= 2.0
      INFO
    end

    request :get_names, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(eq("---\na\nb\n")) }
    end

    request :get_specs do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([["a", Gem::Version.new("0.0.1"), "ruby"]]) }
    end

    request :get_specs, :prerelease do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([["b", Gem::Version.new("1.0.0.pre"), "ruby"]]) }
    end

    request :get_specs, :latest do
      it { is_expected.to be_ok }
      it { is_expected.to unmarshal_as([["a", Gem::Version.new("0.0.1"), "ruby"]]) }
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
        a 0.2.0 66fab29417d3142772e0f2467b92d684
        a 0.2.0-x86-mingw32 fd6d38ccbc3556b4426c65fceed9c717
        a 0.2.0-java 704774b40118bdb16676deee38a99030
      BODY
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~INFO) }
        0.2.0 |checksum:6f2d3eb31a402d2be7c7d51d52e22ba9c86ca7b0641a3debfb3deadedc19301f
        0.2.0-x86-mingw32 |checksum:d2bb53926789434de893cf0a7a872bd887440f6e4edfec15626961d5431aad8a
        0.2.0-java |checksum:63ed6f9d68ebfea869389a9227c8c041b9ed7a0ea68dbe37ee12aaa17406c524
      INFO
    end

    request :get_specs do
      it { is_expected.to be_ok, last_response.body }

      it {
        is_expected.to unmarshal_as(
          a_collection_containing_exactly(*(Marshal.load(Zlib.gunzip(parent_response.body)) + [
            ["a", Gem::Version.new("0.2.0"), "x86-mingw32"],
            ["a", Gem::Version.new("0.2.0"), "ruby"],
            ["a", Gem::Version.new("0.2.0"), "java"]
          ]))
        )
      }
    end

    request :get_specs, :latest do
      it { is_expected.to be_ok }

      it {
        is_expected.to unmarshal_as a_collection_containing_exactly(
          ["a", Gem::Version.new("0.2.0"), "x86-mingw32"],
          ["a", Gem::Version.new("0.2.0"), "ruby"],
          ["a", Gem::Version.new("0.2.0"), "java"]
        )
      }
    end

    request :get_specs, :prerelease do
      it { is_expected.to be_ok }

      it {
        is_expected.to unmarshal_as([["b", Gem::Version.new("1.0.0.pre"), "ruby"]])
      }
    end
  end
  .then "after rebuilding versions list", before: ->(_) { rebuild_versions_list } do
    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(<<~BODY) }
        created_at: 1990-01-01T01:08:00Z
        ---
        a 0.0.1,0.2.0,0.2.0-x86-mingw32,0.2.0-java 704774b40118bdb16676deee38a99030
        b 1.0.0.pre f0d229a9323895e2e1c85f496b5f10b5
      BODY
    end
  end
  .then "after fourth push", before: ->(_) { push_gem(build_gem("a", "0.3.0"), expected_to: be_ok) } do
    pushed_gem("a-0.3.0")

    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~BODY) }
        a 0.3.0 6d832e39a3fcc2e49f17db8023b3db31
      BODY
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + <<~INFO) }
        0.3.0 |checksum:896df5352ce069a200e283d04bf2cbadcc5f779de5a0bb31074a406b3642a8a3
      INFO
    end

    request :get_specs do
      it { is_expected.to be_ok }

      it {
        is_expected.to unmarshal_as a_collection_containing_exactly(
          *(Marshal.load(Zlib.gunzip(parent_response.body)) + [["a", Gem::Version.new("0.3.0"), "ruby"]])
        )
      }
    end

    request :get_specs, :latest do
      it { is_expected.to be_ok }

      it {
        is_expected.to unmarshal_as a_collection_containing_exactly(
          ["a", Gem::Version.new("0.2.0"), "x86-mingw32"],
          ["a", Gem::Version.new("0.2.0"), "java"],
          ["a", Gem::Version.new("0.3.0"), "ruby"]
        )
      }
    end
  end
  .then "after yanking a gem", before: ->(_) { yank_gem(@a_0_2_0, expected_to: be_ok) } do
    yanked_gem("a-0.2.0")

    request :get_versions, compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }
      it { is_expected.to have_body(parent_response.body + "a -0.2.0 474751e9d427e559781d7e222b368085\n") }
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }

      it {
        is_expected.to have_body(
          parent_response.body.lines.tap do |lines|
            lines.delete("0.2.0 |checksum:6f2d3eb31a402d2be7c7d51d52e22ba9c86ca7b0641a3debfb3deadedc19301f\n")
          end.join
        )
      }
    end

    request :get_specs do
      it { is_expected.to be_ok }

      it { is_expected.to have_content_length }
        .metadata[:content_length_header] = true
      it {
        is_expected.to unmarshal_as(
          a_collection_containing_exactly( \
            *Marshal.load(Zlib.gunzip(parent_response.body)).tap do |entries|
              entries.delete(["a", Gem::Version.new("0.2.0"), "ruby"])
            end
          )
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
        a 0.0.1,0.2.0-x86-mingw32,0.2.0-java,0.3.0 474751e9d427e559781d7e222b368085
        b 1.0.0.pre f0d229a9323895e2e1c85f496b5f10b5
      VERSIONS
    end
  end
  .then "after yanking a missing gem", before:
    lambda { |_|
      yank_gem(RequestHelpers::MockGem.new(name: "missing", version: "1.0.0"), expected_to: be_not_found)
    } do # rubocop:disable RSpec/ReturnFromStub
    nil
  end
end
