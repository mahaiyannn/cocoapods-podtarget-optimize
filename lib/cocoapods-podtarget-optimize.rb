require "cocoapods-podtarget-optimize/version"

if Pod::VERSION == '0.35.0'
  puts "cocoapods-podtarget-optimize - 0.35.0"
  module Pod
    class Installer
      # Creates the target for the Pods libraries in the Pods project and the
      # relative support files.
      #
      class PodTargetInstaller < TargetInstaller
        # Creates the target in the Pods project and the relative support files.
        #
        # @return [void]
        #
        def install!
          UI.message "- Installing target `#{target.name}` #{target.platform}" do
            add_target
            create_support_files_dir
            add_files_to_build_phases
            add_resources_bundle_targets
            create_xcconfig_file
            ########################## Added ##########################
            # if the souce build only have dummy.m, ignore this target
            if native_target.source_build_phase.files.count > 0
              create_prefix_header
            else
              project.targets.pop
              target.native_target = nil
              @native_target = nil
            end
            ########################## Added ##########################
          end
        end
      end
    end
  end

  module Pod
    class Installer
      def install_libraries
        UI.message '- Installing targets' do
          pod_targets.sort_by(&:name).each do |pod_target|
            next if pod_target.target_definition.dependencies.empty?
            target_installer = PodTargetInstaller.new(sandbox, pod_target)
            target_installer.install!
          end

          aggregate_targets.sort_by(&:name).each do |target|
            next if target.target_definition.dependencies.empty?
            target_installer = AggregateTargetInstaller.new(sandbox, target)
            target_installer.install!
          end

          # TODO
          # Move and add specs
          pod_targets.sort_by(&:name).each do |pod_target|
            pod_target.file_accessors.each do |file_accessor|
              file_accessor.spec_consumer.frameworks.each do |framework|
                ########################## Added ############################
                # only config when the target is exist
                next if pod_target.native_target.nil?
                ########################## Added ############################
                pod_target.native_target.add_system_framework(framework)
              end
            end
          end
        end
      end

      def set_target_dependencies
        aggregate_targets.each do |aggregate_target|
          aggregate_target.pod_targets.each do |pod_target|
            ########################## Added ############################
            # only config when the target is exist
            next if pod_target.native_target.nil?
            ########################## Added ############################
            aggregate_target.native_target.add_dependency(pod_target.native_target)
            pod_target.dependencies.each do |dep|

              unless dep == pod_target.pod_name
                pod_dependency_target = aggregate_target.pod_targets.find { |target| target.pod_name == dep }
                # TODO remove me
                unless pod_dependency_target
                  puts "[BUG] DEP: #{dep}"
                end
                ########################## Added ############################
                # only config when the target is exist
                next if pod_dependency_target.native_target.nil?
                ########################## Added ############################
                pod_target.native_target.add_dependency(pod_dependency_target.native_target)
              end
            end
          end
        end
      end
    end
  end

  module Pod
    module Generator
      module XCConfig
        # Generates the xcconfigs for the aggregate targets.
        #
        class AggregateXCConfig
          def generate
            header_search_path_flags = target.sandbox.public_headers.search_paths(target.platform)
            @xcconfig = Xcodeproj::Config.new(
                'OTHER_LDFLAGS' => XCConfigHelper.default_ld_flags(target),
                'OTHER_LIBTOOLFLAGS' => '$(OTHER_LDFLAGS)',
                'HEADER_SEARCH_PATHS' => XCConfigHelper.quote(header_search_path_flags),
                'PODS_ROOT' => target.relative_pods_root,
                'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) COCOAPODS=1',
                'OTHER_CFLAGS' => '$(inherited) ' + XCConfigHelper.quote(header_search_path_flags, '-isystem')
            )

            target.pod_targets.each do |pod_target|
              next unless pod_target.include_in_build_config?(@configuration_name)

              pod_target.file_accessors.each do |file_accessor|
                XCConfigHelper.add_spec_build_settings_to_xcconfig(file_accessor.spec_consumer, @xcconfig)
                file_accessor.vendored_frameworks.each do |vendored_framework|
                  XCConfigHelper.add_framework_build_settings(vendored_framework, @xcconfig, target.sandbox.root)
                end
                file_accessor.vendored_libraries.each do |vendored_library|
                  XCConfigHelper.add_library_build_settings(vendored_library, @xcconfig, target.sandbox.root)
                end
              end

              # Add pod static lib to list of libraries that are to be linked with
              # the user’s project.

              ########################## Added ############################
              # only config when the target is exist
              next if pod_target.native_target.nil?
              ########################## Added ############################

              @xcconfig.merge!('OTHER_LDFLAGS' => %(-l "#{pod_target.name}"))
            end

            # TODO Need to decide how we are going to ensure settings like these
            # are always excluded from the user's project.
            #
            # See https://github.com/CocoaPods/CocoaPods/issues/1216
            @xcconfig.attributes.delete('USE_HEADERMAP')

            @xcconfig
          end
        end
      end
    end
  end

end







