# frozen_string_literal: true

require_relative "support/step_helpers"

RSpec.describe GemServerConformance do # rubocop:disable RSpec/EmptyExampleGroup
  include StepHelpers

  before(:all) do
    Gem.configuration.verbose = false
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
          autorequire:
          bindir: bin
          cert_chain: []
          date: 2024-07-09 00:00:00.000000000 Z
          dependencies: []
          description:
          email:
          executables: []
          extensions: []
          extra_rdoc_files: []
          files: []
          homepage:
          licenses: []
          metadata: {}
          post_install_message:
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
          signing_key:
          specification_version: 4
          summary: Conformance test
          test_files: []
        YAML
           header: { checksum: 5892,
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
                     size: 365,
                     typeflag: "0",
                     uid: 0,
                     uname: "wheel",
                     version: 0 } },
         { body: [],
           header: { checksum: 5833,
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
                     size: 20,
                     typeflag: "0",
                     uid: 0,
                     uname: "wheel",
                     version: 0 } },
         { body: <<~YAML,
           ---
           SHA256:
             metadata.gz: 91310c40bdbd518a6b77e0277f73f7a7d8b4d3f9aadbbf8e62adb2b63c8e61d1
             data.tar.gz: f61f27bd17de546264aa58f40f3aafaac7021e0ef69c17f6b1b4cd7664a037ec
           SHA512:
             metadata.gz: f62de0d02c815d25499d0b27fcc4ca0cf61d35df51bcc0c613eb30520226629f962a3c57447dfb99e03a554043bdaa2736eeb2aa4af06e41f09337efda96521e
             data.tar.gz: 1b46b9b08d5b338be9d732a1724795b2eab63daffde377218727c90857b79fe6a47bceed495117fcde60f7339812ef75ef4c69f82dd79fb69b6cbf8006b521f2
         YAML
           header: { checksum: 6500,
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
                     size: 296,
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
      it { is_expected.to have_body(parent_response.body + "a -0.2.0 1fdcc4d621638a6ba75d8ed88b09f97a\n") }
    end

    request :get_info, "a", compact_index: true do
      it { is_expected.to be_valid_compact_index_reponse }

      it {
        is_expected.to have_body(
          parent_response.body.lines.tap do |lines|
            lines.delete("0.2.0 |checksum:a1753a0e8b6f0515a15e9cfa4ea143e36de235525f6f68c4ff45c4ae70be072f\n")
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
        a 0.0.1,0.2.0-x86-mingw32,0.2.0-java,0.3.0 1fdcc4d621638a6ba75d8ed88b09f97a
        b 1.0.0.pre 688f5cdf79887aff5d87c86f36cfe063
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
