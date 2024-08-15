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

## Workaround a change in minitest 1.15 that triggered a weird bug, causing ruby
## tests to fail with cannot create Thread: reosource temporarily unavailable
##
## This seem to be only triggered when tests are run under autoproj (the weird part)
Autoproj.env_set "MT_CPU", "1"

# Setup our "rubocop version manager"
#
# This is a script that auto-installs and auto-starts different version of
# rubocop based on a .rubocop-version file in the packages. This is meant as a
# way to smoothly migrate away from rubocop 0.83.0 ... which we are stuck on for
# a long while now
Autoproj.env_add_path "PATH", File.join(File.expand_path(__dir__), "rubocop-bin")
Autoproj.env_set "RUBOCOP_VERSION_MANAGER_ROOT",
                 File.join(Autoproj.workspace.prefix_dir, "rubocop-versions")
Autoproj.env_set "RUBOCOP_VERSION_MANAGER_DEFAULT", "0.83.0"

rubocop_gemfile = Autoproj.config.get(
    "rubocop-manager-gemfile",
    File.expand_path("Gemfile.rubocop", __dir__)
)
if rubocop_gemfile
    Autoproj.env_set "RUBOCOP_VERSION_MANAGER_GEMFILE", rubocop_gemfile
end
Autoproj.env.set "RUBOCOP_CMD", "rubocop-manager"

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

require File.join(__dir__, 'rock/flavor_definition')
require File.join(__dir__, 'rock/flavor_manager')
require File.join(__dir__, 'rock/in_flavor_context')
require File.join(__dir__, 'rock/current_release')
require File.join(__dir__, 'rock/python')

Rock.flavors.define 'stable'
Rock.flavors.alias 'stable', 'next'
Rock.flavors.define 'master', :implicit => true

configuration_option('ROCK_SELECTED_FLAVOR', 'string',
    :default => 'master',
    :possible_values => ['stable', 'master'],
    :doc => [
        "Which flavor of Rock do you want to use ?",
        "Stay with the default ('master') if you want to use Rock on the most recent",
        "distributions (Ubuntu 16.04 and later). Use 'stable' only for ",
        "now officially unsupported distributions (Ubuntu 14.04)"])

if Rock.in_release? && !Autoproj.config.has_value_for?('ROCK_SELECTED_FLAVOR')
    Autoproj.config.set 'ROCK_SELECTED_FLAVOR', 'stable', true
end

Rock.flavors.select_current_flavor_by_name(
    ENV['ROCK_FORCE_FLAVOR'] || Autoproj.config.get('ROCK_SELECTED_FLAVOR'))

current_flavor = Rock.flavors.current_flavor

#This check is needed because the overrides file will override the FLAVOR selection.
#Furthermore a selection != stable can cause a inconsistent layout (cause by in_flavor system in the package_sets)
if Rock.in_release? && current_flavor.branch != "stable" 
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

require File.join(__dir__, 'rock', 'cxx')
if Autoproj.respond_to?(:workspace) # autoproj 2.0
    Rock.setup_cxx_support(Autoproj.workspace.os_package_resolver, Autoproj.config)
else
    Rock.setup_cxx_support(Autoproj.osdeps, Autoproj.config)
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

Rock.setup_python_configuration_options

Autoproj.config.declare 'syskit_use_bundles', 'boolean',
    default: true,
    short_doc: 'whether Syskit systems should load Rock\'s bundle plugin',
    doc: ['Whether Syskit bundles should be loading the Rock bundle system',
          'The Rock bundle system may be loaded in Syskit, to apply the ROCK_BUNDLE_*',
          'environment variables to the Syskit apps. This is fragile, we recommend',
          'setting it to OFF and explicitely using Syskit\'s Roby.app.register_app',
          'mechanism. It is ON by default for backward compatibility reasons']

unless Autoproj.config.has_value_for?('syskit_use_bundles')
    Autoproj.config.set 'syskit_use_bundles', true, true
end

Autoproj.config.declare 'build_visualization', 'boolean',
    default: true,
    short_doc: 'Whether vizkit visualizaztion plugins in "viz" subfolders of packages should be built',
    doc: ['Should the visualizations be built (viz subfolder of packages)?',
        'This will also evaluate the manifest.xml in the viz subfolder of a package',
        'and install them',
        'These dependencies will appear as dependencies of the main package']

unless Autoproj.config.has_value_for?('build_visualization')
    Autoproj.config.set 'build_visualization', true, true
end
