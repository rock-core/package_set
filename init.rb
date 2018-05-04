# Orocos Specific ignore rules
#
# Ignore log files generated from the orocos/orogen components
ignore(/\.log$/, /\.ior$/, /\.idx$/)
# Ignore all text files except CMakeLists.txt
ignore(/(^|\/)(?!CMakeLists)[^\/]+\.txt$/)
# We don't care about the manifest being changed, as autoproj *will* take
# dependency changes into account
ignore(/manifest\.xml$/)
# Ignore vim swap files
ignore(/\.sw?$/)
# Ignore the numerous backup files
ignore(/~$/)


# Ruby 1.8 is completly outdated, if you modify this, take respect to the addition checks below against 1.9 
if RUBY_VERSION < "2.1"
    Autoproj.error "Rock requires Ruby version 2.1 or later"
    Autoproj.error ""
    Autoproj.error "If you really want to bypass this check set the"
    Autoproj.error "ROCK_IGNORE_RUBY_VERSION environment variable to 1"
    Autoproj.error ""
    Autoproj.error "See http://rock-robotics.org/stable/documentation/installation.html for more information"

    if ENV['ROCK_IGNORE_RUBY_VERSION'] != '1'
        exit 1
    end
end

require 'autoproj/gitorious'
if !Autoproj.has_source_handler? 'github'
    Autoproj.gitorious_server_configuration('GITHUB', 'github.com', :http_url => 'https://github.com')
end

require File.join(File.dirname(__FILE__), 'rock/flavor_definition')
require File.join(File.dirname(__FILE__), 'rock/flavor_manager')
require File.join(File.dirname(__FILE__), 'rock/in_flavor_context')

Rock.flavors.define 'stable'
Rock.flavors.alias 'stable', 'next'
Rock.flavors.define 'master', :implicit => true

configuration_option('ROCK_SELECTED_FLAVOR', 'string',
    :default => 'stable',
    :possible_values => ['stable', 'master'],
    :doc => [
        "Which flavor of Rock do you want to use ?",
        "Use 'stable' to use the a released version of Rock that gets updated with bugfixes", "'master' for the development branch","If you want to use a released version of rock, choose 'stable' and then call 'rock-release switch' after the initial bootstrap", "See http://rock-robotics.org/stable/documentation/installation.html for more information"])


Rock.flavors.select_current_flavor_by_name(
    ENV['ROCK_FORCE_FLAVOR'] || Autoproj.config.get('ROCK_SELECTED_FLAVOR'))

current_flavor = Rock.flavors.current_flavor

#This check is needed because the overrides file will override the FLAVOR selection.
#Furthermore a selection != stable can cause a inconsistent layout (cause by in_flavor system in the package_sets)
if File.exists?(File.join(Autoproj.root_dir, "autoproj", "overrides.d", "25-release.yml")) && current_flavor.branch != "stable" 
    if ENV['ROCK_RC'] == '1'
        Autoproj.warn ""
        Autoproj.warn "Found a release file and the flavor is not master"
        Autoproj.warn "This would usually be an error, but since ROCK_RC is set to 1,"
        Autoproj.warn "it is assumed that you're preparing a release candidate"
        Autoproj.warn ""
    else
        Autoproj.error ""
        Autoproj.error "You selected the flavor '#{current_flavor.branch}' but '#{File.join(Autoproj.root_dir,"autoproj", "overrides.d", "25-release.yml")}' exists."
        Autoproj.error "This means you are on a release; either unselect the release by calling 'rock-release switch master'"
        Autoproj.error "or call 'autoproj reconfigure' and select the FLAVOR 'stable'"
        exit 1
    end
end

Autoproj.config.set('ROCK_SELECTED_FLAVOR', current_flavor.name, true)
Autoproj.config.set('ROCK_FLAVOR', current_flavor.branch, true)
Autoproj.config.set('ROCK_BRANCH', current_flavor.branch, true)

if current_flavor.name != 'master' && Autoproj::PackageSet.respond_to?(:add_source_file)
    Autoproj::PackageSet.add_source_file "source-stable.yml"
end

require File.join(__dir__, 'rock', 'cxx11')
if Autoproj.respond_to?(:workspace) # autoproj 2.0
    Rock.setup_cxx11_support(Autoproj.workspace.os_package_resolver, Autoproj.config)
else
    Rock.setup_cxx11_support(Autoproj.osdeps, Autoproj.config)
end

def enabled_flavor_system
    Rock.flavors.register_flavored_package_set(Autoproj.current_package_set)
end

def in_flavor(*flavors, &block)
    Rock.flavors.in_flavor(*flavors, &block)
end

def only_in_flavor(*flavors, &block)
    Rock.flavors.only_in_flavor(*flavors, &block)
end

def flavor_defined?(flavor_name)
    Rock.flavors.has_flavor?(flavor_name)
end

def package_in_flavor?(pkg, flavor_name)
    Rock.flavors.package_in_flavor?(pkg, flavor_name)
end

def add_packages_to_flavors(mappings)
    Rock.flavors.add_packages_to_flavors(Autoproj.current_package_set, mappings)
end

def remove_packages_from_flavors(mappings)
    Rock.flavors.remove_packages_from_flavors(Autoproj.current_package_set, mappings)
end

# Defines a bundle package in the installation
#
# So far, bundles are mostly Ruby packages
def bundle_package(*args, &block)
    ruby_package(*args) do |pkg|
        if block_given?
            pkg.instance_eval(&block)
        end
    end
end

# rtt doesn't support mqueue on Mac OS X
if Autobuild.macos?
    Autobuild::Orogen.transports.delete("mqueue")
end

