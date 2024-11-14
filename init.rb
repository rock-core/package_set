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

require File.join(__dir__, 'rock/current_release')
require File.join(__dir__, 'rock/python')


# backward compatibility for the deprecated flavor system
if !Autoproj.config.has_value_for?('ROCK_SELECTED_FLAVOR') then
    Autoproj.config.set('ROCK_SELECTED_FLAVOR', "master")
end
if !Autoproj.config.has_value_for?('ROCK_FLAVOR') then
    Autoproj.config.set('ROCK_FLAVOR', "master")
end
if !Autoproj.config.has_value_for?('ROCK_BRANCH') then
    Autoproj.config.set('ROCK_BRANCH', "master")
end


def enabled_flavor_system
    Autoproj.warn "Flavors system was removed, please remove flavor-related code from your package_sets"
end

def in_flavor(*flavors, &block)
    Autoproj.warn "Flavors system was removed, please remove flavor-related code from your package_sets"
    return false
end
    
def only_in_flavor(*flavors, &block)
    Autoproj.warn "Flavors system was removed, please remove flavor-related code from your package_sets"
end

def flavor_defined?(flavor_name)
    Autoproj.warn "Flavors system was removed, please remove flavor-related code from your package_sets"
    return false
end
    
def package_in_flavor?(pkg, flavor_name)
    Autoproj.warn "Flavors system was removed, please remove flavor-related code from your package_sets"
    return false
end
    
def add_packages_to_flavors(mappings)
    Autoproj.warn "Flavors system was removed, please remove flavor-related code from your package_sets"
end
   
def remove_packages_from_flavors(mappings)
    Autoproj.warn "Flavors system was removed, please remove flavor-related code from your package_sets"
end

require File.join(__dir__, 'rock', 'cxx')
if Autoproj.respond_to?(:workspace) # autoproj 2.0
    Rock.setup_cxx_support(Autoproj.workspace.os_package_resolver, Autoproj.config)
else
    Rock.setup_cxx_support(Autoproj.osdeps, Autoproj.config)
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

# See README
if (sanitizers = Autoproj.config.get("cxx_sanitizers", nil))
    list = sanitizers.split(",")
    if list.include?("address")
        asan_lib_path = Autoproj.config.get("libasan_path", nil)
        unless asan_lib_path
            raise "you enabled the ASan sanitizer, but did not set the libasan_path configuration variable. Set it to the path to the libasan shared library"
        end
        Autoproj.env_add_path "LD_PRELOAD", asan_lib_path
        Autoproj.env_set "LSAN_OPTIONS", "exitcode=0"
        Autoproj.env_set "ASAN_OPTIONS", "detect_leaks=0"
    end
end

