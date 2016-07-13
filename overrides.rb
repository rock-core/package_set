# Migration from old-style .h base/types package to Rock-standard Bla.hpp
# package
base_types = package('base/types')
base_types.post_import do
    if File.file?(File.join(base_types.srcdir, 'base', 'Time.hpp'))
        includedir = File.join(base_types.prefix, 'include', 'base')
        if File.file?(File.join(includedir, 'time.h'))
            Autoproj.warn "deleting #{includedir} because of change in include structure"
            FileUtils.rm_rf includedir
            FileUtils.rm_rf base_types.installstamp
        end
    end
end

Rock.flavors.finalize
switched_packages = Rock.flavors.reset_invalid_branches_to('master')
wrong_branch = Rock.flavors.find_all_overriden_flavored_branches

if !switched_packages.empty?
    pkgs = switched_packages.sort_by { |pkg, _| pkg.name }.
        map do |pkg, original_branch|
            "#{pkg.name} (branch=#{original_branch})"
        end

    Autoproj.warn ""
    Autoproj.warn "the following packages are using a branch which is incompatible with the flavors"
    Autoproj.warn "they are included in (as e.g. using the 'next' branch while being included only on 'master')."
    Autoproj.warn "they got switched back to master"
    Autoproj.warn "  #{pkgs.join(", ")}"
end

wrong_branch -= switched_packages
wrong_branch = wrong_branch.find_all { |pkg| pkg.importer.branch != 'rock-rc' }
if !wrong_branch.empty?
    pkgs = wrong_branch.map { |pkg| "#{pkg.name}(#{pkg.importer.branch})" }.join(", ")

    Autoproj.warn ""
    Autoproj.warn "the following packages are using a different branch than the current flavor"
    Autoproj.warn "it is assumed that it is intentional"
    Autoproj.warn "  #{pkgs}"
end

require File.join(File.dirname(__FILE__), 'rock/git_hook')
require File.join(File.dirname(__FILE__), 'rock/cmake_build_type')
Autoproj.post_import do |pkg|
    if pkg.kind_of?(Autobuild::CMake)
        Rock.update_cmake_build_type_from_tags(pkg)
    end
    if pkg.importer.kind_of?(Autobuild::Git)
        if pkg.importer.branch == "next" || pkg.importer.branch == "stable"
            Rock.install_git_hook pkg, 'git_do_not_commit_hook', 'pre-commit'
        else
            Rock.remove_git_hook pkg, 'pre-commit'
        end
    end
end

Autoproj.env_add_path 'ROCK_BUNDLE_PATH', File.join(Autobuild.prefix, 'share', 'rock')
Autoproj.env_add_path 'ROCK_BUNDLE_PATH', File.join(Autoproj.root_dir, 'bundles')

# Finally, verify that when pkg A from flavor X depends on pkg B, then B needs
# to be available in flavor X as well
if ENV['ROCK_DISABLE_CROSS_FLAVOR_CHECKS'] != '1'
    Autoproj.post_import do |pkg|
        next if !pkg.importer.kind_of?(Autobuild::Git)
        Rock.flavors.verify_cross_flavor_dependencies(pkg)
    end
end

Autoproj.manifest.each_autobuild_package do |pkg|
    next if !pkg.kind_of?(Autobuild::Orogen)
    if pkg.name != "tools/logger" && pkg.name != "base/orogen/types" && pkg.name != 'base/orogen/std'
        pkg.optional_dependency 'tools/logger'
    end
                                                       #ugly but we hav eno other way if we build a RC
    if Rock.flavors.current_flavor.name == 'master' && package('base/orogen/std').importer.branch != 'rock-rc' 
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
end

# 2014-03-12:
# temporary fix for boost bug: https://svn.boost.org/trac/boost/ticket/7979
# on debian testing
only_on 'debian' do
  setup_package 'typelib' do |pkg|
      pkg.define "GLIBC_HAVE_LONG_LONG", 1
  end  
end

# Manage the Rock standard flag for tests
Autoproj.post_import do |pkg|
   if pkg.kind_of?(Autobuild::CMake)
      pkg.define "ROCK_TEST_ENABLED", pkg.test_utility.enabled?
   end
end

# enabling the compile_commands feature for cmake based projects. allows for
# example usage of semantic c/c++ completion tools.
#
# see https://rock.opendfki.de/ticket/384
Autoproj.post_import do |pkg|
   if pkg.kind_of?(Autobuild::CMake)
      pkg.define "CMAKE_EXPORT_COMPILE_COMMANDS", "ON"
   end
end

if Autoproj.user_config 'cxx11'
    Autoproj.post_import do |pkg|
        if pkg.kind_of?(Autobuild::CMake)
            pkg.define "ROCK_USE_CXX11", "TRUE"
        end
    end
end

