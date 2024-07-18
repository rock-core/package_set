Rock.flavors.finalize
wrong_branch = Rock.flavors.find_all_overriden_flavored_branches

wrong_branch = wrong_branch.find_all { |pkg| pkg.importer.branch != 'rock-rc' }
if !wrong_branch.empty?
    pkgs = wrong_branch.map { |pkg| "#{pkg.name}(#{pkg.importer.branch})" }.join(", ")

    Autoproj.warn ""
    Autoproj.warn "the following packages are using a different branch than the current flavor"
    Autoproj.warn "it is assumed that it is intentional"
    Autoproj.warn "  #{pkgs}"
end

Autoproj.env_add_path 'ROCK_BUNDLE_PATH', File.join(Autobuild.prefix, 'share', 'rock')
Autoproj.env_add_path 'ROCK_BUNDLE_PATH', File.join(Autoproj.root_dir, 'bundles')

require File.join(__dir__, 'rock', 'git_hook')
require File.join(__dir__, 'rock', 'cmake_build_type')
Autoproj.manifest.each_autobuild_package do |pkg|
    case pkg.importer
    when Autobuild::Git
        if ENV['ROCK_DISABLE_CROSS_FLAVOR_CHECKS'] != '1'
            # Finally, verify that when pkg A from flavor X depends on pkg B,
            # then B needs to be available in flavor X as well
            Rock.flavors.verify_cross_flavor_dependencies(pkg)
        end

        # Do the git hook setup in a separate setup block since we must do it
        # post-import
        pkg.post_import do
            if pkg.importer.branch == "next" || pkg.importer.branch == "stable"
                Rock.install_git_hook pkg, 'git_do_not_commit_hook', 'pre-commit'
            else
                Rock.remove_git_hook pkg, 'pre-commit'
            end
        end
    end

    # NOTE: do not use a case/when to dispatch the package types.
    # Autobuild::Orogen is a subclass of Autobuild::CMake - and therefore needs
    # to get through both ifs. It's not the case with Autobuild::Ruby, but I
    # think it's easier to just have a bunch of ifs

    if pkg.kind_of?(Autobuild::Orogen)
        if !%w{tools/logger base/orogen/types base/orogen/std}.include?(pkg.name)
            pkg.optional_dependency 'tools/logger'
        end
        if Rock.flavors.current_flavor.name == 'master'
            pkg.orogen_options << '--extensions=metadata_support'
            pkg.depends_on 'tools/orogen_metadata'
        end
        if pkg.name != 'base/orogen/std'
            pkg.optional_dependency 'base/orogen/std'
            pkg.orogen_options << '--import=std'
        end
        pkg.optional_dependency 'tools/service_discovery'
        if !Autoproj.config.get('USE_OCL')
            pkg.optional_dependencies.delete 'ocl'
        end

        pkg.post_import do
            pkg.orogen_options << "--test" if pkg.test_utility.enabled?
        end
    end

    if pkg.kind_of?(Autobuild::Ruby) && Autoproj.config.get("test_junit_output", true)
        pkg.post_import do
            if pkg.test_utility.enabled?
                pkg.depends_on "minitest-junit"
                pkg.rake_test_options.concat([
                    "TESTOPTS=--junit --junit-jenkins "\
                    "--junit-filename=#{pkg.test_utility.source_dir}/report.junit.xml",
                    "RUBOCOP=1", "JUNIT=1", "REPORT_DIR=#{pkg.test_utility.source_dir}"
                ])
            end
        end
    end

    if pkg.kind_of?(Autobuild::CMake)
        if File.directory?(File.join(pkg.srcdir, 'viz'))
            if Autoproj.config.has_value_for?('build_visualization')
                if Autoproj.config.get 'build_visualization'
                    pkg.define 'ROCK_VIZ_ENABLED', 'OFF'
                else
                    # load manifest.xml from viz folder
                    viz_manifest_file = File.join(pkg.srcdir, 'viz', 'manifest.xml')
                    if File.file?(viz_manifest_file)
                        manifest = Autoproj::PackageManifest.load(pkg, viz_manifest_file, ros_manifest: false)
                        if manifest
                            manifest.each_dependency do |name, is_optional|
                                if is_optional
                                    pkg.optional_dependency name
                                else
                                    pkg.depends_on name
                                end
                            end
                        end
                    end
                end
            end
        end

        pkg.post_import do
            Rock.update_cmake_build_type_from_tags(pkg)

            # Augment autoproj's autodetection of test tasks to handle
            # bindings/ruby
            unless pkg.test_utility.source_dir && Autoproj.config.get("test_junit_output", true)
                ruby_test_dir = File.join(pkg.srcdir, 'bindings', 'ruby', 'test')
                if File.directory?(ruby_test_dir)
                    pkg.test_utility.source_dir =
                        File.join(pkg.builddir, 'test', 'results')
                    FileUtils.mkdir_p File.join(pkg.builddir, 'test', 'results')
                    pkg.with_tests
                end
            end

            if File.directory?(File.join(pkg.srcdir, 'viz'))
                pkg.env_add_path 'VIZKIT_PLUGIN_RUBY_PATH', File.join(pkg.prefix, 'lib')
            end
            pkg.define 'ROCK_TEST_ENABLED', pkg.test_utility.enabled? ? "ON" : "OFF"
            if pkg.test_utility.enabled?
                pkg.depends_on 'minitest-junit'
                pkg.define 'ROCK_TEST_LOG_DIR', pkg.test_utility.source_dir
                pkg.define 'ROCK_TEST_BOOST_FORMAT',
                           pkg.ws.config.get('rock_test_boost_format', 'XML')
            end
        end
        pkg.define 'CMAKE_EXPORT_COMPILE_COMMANDS', 'ON'
        pkg.env_add_path 'QT_PLUGIN_PATH', File.join(pkg.prefix, 'lib', 'qt')
    end
end

# 2014-03-12:
# temporary fix for boost bug: https://svn.boost.org/trac/boost/ticket/7979
# on debian testing
only_on 'debian' do
    setup_package 'typelib' do |pkg|
        pkg.define "GLIBC_HAVE_LONG_LONG", 1
    end
end

