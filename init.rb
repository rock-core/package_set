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
if defined?(RUBY_VERSION) && (RUBY_VERSION =~ /^1\.8\./)
    Autoproj.error "Ruby 1.8 is not supported by Rock anymore"
    Autoproj.error ""
    Autoproj.error "Use Rock's bootstrap.sh script to install Rock"
    Autoproj.error "See http://rock-robotics.org/stable/documentation/installation.html for more information"
    exit 1
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

def add_compiler_flag(var_name, value)
    cur_val = Autobuild.env_value var_name
    if cur_val
        cur_val = cur_val.join ' '
        if !cur_val.include? value
            value.concat ' '
            value.concat cur_val
        end
    end
    Autobuild.env_set var_name, value
end

configuration_option('ROCK_SELECTED_FLAVOR', 'string',
    :default => 'stable',
    :possible_values => ['stable', 'master'],
    :doc => [
        "Which flavor of Rock do you want to use ?",
        "Use 'stable' to use the a released version of Rock that gets updated with bugfixes", "'master' for the development branch","If you want to use a released version of rock, choose 'stable' and then call 'rock-release switch' after the initial bootstrap", "See http://rock-robotics.org/stable/documentation/installation.html for more information"])


Rock.flavors.select_current_flavor_by_name(
    ENV['ROCK_FORCE_FLAVOR'] || Autoproj.config.get('ROCK_SELECTED_FLAVOR'))

current_flavor = Rock.flavors.current_flavor

Autoproj.configuration_option 'cxx11', 'boolean',
:default => 'yes',
:doc => ["Compile with Cxx11 ? [yes/no]"]

if Autoproj.user_config 'cxx11'
    add_compiler_flag 'CXXFLAGS', "-std=c++11"
end

#This check is needed because the overrides file will override the FLAVOR selection.
#Furthermore a selection != stable can cause a inconsistent layout (cause by in_flavor system in the package_sets)
if File.exists?(File.join(Autoproj.root_dir, "autoproj", "overrides.d", "25-release.yml")) && current_flavor.branch != "stable" 
    Autoproj.error ""
    Autoproj.error "You selected the flavor '#{current_flavor.branch}' but '#{File.join(Autoproj.root_dir,"autoproj", "overrides.d", "25-release.yml")}' exists."
    Autoproj.error "This means you are on a release; either unselect the release by calling 'rock-release switch master'"
    Autoproj.error "or call 'autoproj reconfigure' and select the FLAVOR 'stable'"
    exit 1
end

Autoproj.config.set('ROCK_SELECTED_FLAVOR', current_flavor.name, true)
Autoproj.config.set('ROCK_FLAVOR', current_flavor.branch, true)
Autoproj.config.set('ROCK_BRANCH', current_flavor.branch, true)

if current_flavor.name != 'master' && Autoproj::PackageSet.respond_to?(:add_source_file)
    Autoproj::PackageSet.add_source_file "source-stable.yml"
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

# Verify that a valid ruby version i used
if defined?(RUBY_VERSION) && (RUBY_VERSION.to_f < 2.0) && Autoproj.config.get('ROCK_FLAVOR') == 'master'
    Autoproj.error "Ruby below 2.0 is not supported by Rock anymore."
    Autoproj.error "Please re-bootstrap your installation."
    Autoproj.error "We recommend ruby 2.1 expect for Ubuntu 14.04 where ruby 2.0 should be used."
    Autoproj.error "You have also the option to switch to the 'stable' flavor by running 'autoproj reconfigure'"
    Autoproj.error "or use the rock-15.05 release by first switching to 'stable' and then running 'rock-release switch rock-15.05'."
    Autoproj.error "If you need to check the state of this installation (to make sure everyting is pushed) you could run"
    Autoproj.error "'ROCK_IGNORE_RUBY_VERSION=1 autoproj status'."
    Autoproj.error ""
    Autoproj.error "See http://rock-robotics.org/documentation/installation.html for more information regarding bootstrapping."
    if !ENV['ROCK_IGNORE_RUBY_VERSION']
        exit 1
    end
end


# rtt doesn't support mqueue on Mac OS X
if Autobuild.macos?
    Autobuild::Orogen.transports.delete("mqueue")
end
