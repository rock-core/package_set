require 'open3'
require 'rubygems'
# Usage:
# In init.rb
#      Rock.setup_python_configuration_options()
# Note, that the setup is done in / part of the rock-core package set
#
# In lib.autobuild
#      cmake_package 'tools/yourpackage' do |pkg|
#          Rock.activate_python_path(pkg)
#      end
#
# Assumptions:
#     0. a python installation must be available
#     1. only a single python version is set in the configuration for all
#           packages  (vs. storing a configuration per package)
#     2. activation takes place through a single call to Rock.activate_python in
#               init.rb
#     3. per package the python path can be updated/activated based on
#              the existing configuration (default), or a custom binary
#              (however, no caching is done for that part)
#     4. version constraints are checked upon activation
module Rock
    # Get the python version for a given python executable
    # @return [String] The python version as <major>.<minor>
    def self.get_python_version(python_bin)
        if !File.exist?(python_bin)
            raise ArgumentError, "Rock.get_python_version executable "\
                        "'#{python_bin}' does not exist"
        end

        cmd = "#{python_bin} -c \"import sys;"\
            "version=sys.version_info[:3]; "\
            "print('{0}.{1}'.format(*version))\"".strip()

        msg, status = Open3.capture2e(cmd)
        if status.success?
            python_version = msg.strip()
            return python_version
        else
            raise RuntimeError, "Rock.get_python_version identification"\
                " of python version for '#{python_bin}' failed: #{msg}"
        end
    end

    def self.get_pip_version(pip_bin)
        if !File.exist?(pip_bin)
            raise ArgumentError, "Rock.get_pip_version executable "\
                        "'#{pip_bin}' does not exist"
        end

        cmd = "#{pip_bin} --version"

        msg, status = Open3.capture2e(cmd)
        if status.success?
            pip_version = msg.split(" ")[1]
            return pip_version
        else
            raise RuntimeError, "Rock.get_pip_version identification"\
                " of pip version for '#{pip_bin}' failed: #{msg}"
        end
    end

    def self.validate_version(version, version_constraint)
        if !version_constraint
            return true
        else
            dependency = Gem::Dependency.new("python", version_constraint)
            return dependency.match?("python", version)
        end
    end

    # Validate that a given python executable's version fulfills
    # a given version constraint
    # @param [String] python_bin the python executable
    # @param [String] version_constraint version constraint, e.g., <3.8, >= 3.7, 3.6
    # @return [String,Bool] Version and validation result, i.e., True if binary fulfills the version constraint, false
    #   otherwise
    def self.validate_python_version(python_bin, version_constraint)
        version = get_python_version(python_bin)
        return [version, validate_version(version, version_constraint)]
    end

    # Find python given a version constraint
    # @return [String,String] path to python executable and python version
    def self.find_python(ws: Autoproj.workspace,
                         version: ws.config.get('python_version',nil))
        finders = [
            lambda { Autobuild.programs['python'] },
            lambda { `which python3`.strip() },
            lambda { `which python`.strip() }
        ]

        finders.each do |finder|
            python_bin = finder.call
            if python_bin && !python_bin.empty?
                python_version, valid = validate_python_version(python_bin, version)
                if valid
                    return python_bin, python_version
                end
            end
        end
        raise RuntimeError, "Rock.find_python_bin: failed to find python" \
            " for version '#{version}'"
    end

    # Get information about the python executable from autoproj config,
    # but ensure the version constraint matches
    #
    # @return [String, String] Return path and version if the constraints
    #      are fulfilled nil otherwise

    def self.get_python_from_config(ws: Autoproj.workspace, version: nil)
        config_bin = ws.config.get('python_executable', nil)
        return unless config_bin

        config_version = ws.config.get('python_version', nil)
        config_version ||= get_python_version(config_bin)

        # If a version constraint is given, ensure fulfillment
        if validate_version(config_version, version)
            return config_bin, config_version
        else
            raise RuntimeError, "python_executable in autoproj config with version '#{config_version}'"\
                " does not match version constraints '#{version}'"
        end
    end

    def self.custom_resolve_python(ws: Autoproj.workspace,
                                   bin: nil,
                                   version: nil)
        version, valid = validate_python_version(bin, version)
        if valid
            return [bin, version]
        else
            raise RuntimeError, "Rock.resolve_python: requested python"\
                "executable '#{bin}' does not satisfy version"\
                "constraints '#{version}'"
        end
    end

    def self.auto_resolve_python(ws: Autoproj.workspace,
                                 version: nil)
        version_constraint = version
        resolvers = [
            lambda { get_python_from_config(ws: ws, version: version_constraint) },
            lambda { find_python(ws: ws, version: version_constraint) }
        ]

        bin = nil
        resolvers.each do |resolver|
            begin
                bin, version = resolver.call
                if bin && File.exist?(bin) && version
                    Autoproj.debug "Rock.resolve_python: found python '#{bin}'"\
                        " version '#{version}'"
                    break
                end
            rescue RuntimeError => e
                Autoproj.debug "Rock.resolve_python: resolver failed: #{e}"
            end
        end

        if !bin
            msg = "Rock.resolve_python: failed to find a python executable"
            if version_constraint
                msg += " satisfying version constraint '#{version_constraint}'"
            end
            raise RuntimeError, msg
        end
        [bin, version]
    end

    # Resolve the python executable according to a given version constraint
    # @param [Autoproj.workspace] ws Autoproj workspace
    # @param [String] bin Path to the python executable that shall be used,
    #   first fallback is the python_executable set in Autoproj's configuration,
    #   second fallback is a full search
    # @param [String] version version constraint
    # @return [String,String] python path and python version
    def self.resolve_python(ws: Autoproj.workspace,
                            bin: nil,
                            version: nil)
        version_constraint = version
        # Custom selection of python version
        if bin
            return custom_resolve_python(ws: ws, bin: bin, version: version)
        else
            return auto_resolve_python(ws: ws, version: version)
        end
    end
    def self.remove_python_shims(root_dir)
        shim_path = File.join(root_dir, "install","bin","python")
        if File.exist?(shim_path)
            FileUtils.rm shim_path
        end
    end

    def self.rewrite_python_shims(python_executable, root_dir)
        shim_path = File.join(root_dir, "install","bin")
        if !File.exist?(shim_path)
            FileUtils.mkdir_p shim_path
            Autoproj.warn "Rock.rewrite_python_shims: creating "\
                "#{shim_path} - "\
                "are you operating on a valid autoproj workspace?"
        end

        python_path = File.join(shim_path, 'python')
        File.open(python_path, 'w') do |io|
            io.puts "#! /bin/sh"
            io.puts "exec #{python_executable} \"$@\""
        end
        FileUtils.chmod 0755, python_path
        python_path
    end

    def self.rewrite_pip_shims(python_executable, root_dir)
        shim_path = File.join(root_dir, "install","bin")
        if !File.exist?(shim_path)
            FileUtils.mkdir_p shim_path
            Autoproj.warn "Rock.rewrite_pip_shims: creating "\
                "#{shim_path} - "\
                "are you operating on a valid autoproj workspace?"
        end
        pip_path = File.join(shim_path, 'pip')
        File.open(pip_path, 'w') do |io|
            io.puts "#! /bin/sh"
            io.puts "exec #{python_executable} -m pip \"$@\""
        end
        FileUtils.chmod 0755, pip_path
        pip_path
    end

    # Activate configuration for python in the autoproj configuration
    # @return [String,String] python path and python version
    def self.activate_python(ws: Autoproj.workspace,
                             bin: nil,
                             version: nil)
        bin, version = resolve_python(ws: ws, bin: bin, version: version)
        ws.config.set('python_executable', bin, true)
        ws.config.set('python_version', version, true)

        ws.osdep_suffixes << "python#{$1}" if version =~ /^([0-9]+)\./

        rewrite_python_shims(bin, ws.root_dir)
        rewrite_pip_shims(bin, ws.root_dir)
        [bin, version]
    end

    def self.deactivate_python(ws: Autoproj.workspace)
        remove_python_shims(ws.root_dir)
        ws.config.reset('python_executable')
        ws.config.reset('python_version')
    end

    # Allow to update the PYTHONPATH for package if autoproj configuration
    # USE_PYTHON is set to true.
    # Then tries to guess the python binary from Autobuild.programs['python']
    # and system's default setting
    # @param [Autobuild::Package] pkg
    # @param [Autoproj.workspace] ws Autoproj workspace
    # @param [String] bin Path to a custom python version
    # @param [String] version version constraint for python executable
    # @return tuple of [executable, version, site-packages path] if set,
    #    otherwise nil
    def self.activate_python_path(pkg,
                             ws: Autoproj.workspace,
                             bin: nil,
                             version: nil)
        return unless ws.config.get('USE_PYTHON',nil)

        bin, version = resolve_python(ws: ws, bin: bin, version: version)
        path = File.join(pkg.prefix, "lib",
                             "python#{version}","site-packages")
        pkg.env_add_path 'PYTHONPATH', path

        [bin, version, path]
    end

    def self.setup_python_configuration_options(ws: Autoproj.workspace)
        ws.config.declare 'USE_PYTHON', 'boolean',
            default: 'no',
            doc: [ "Do you want to activate python?" ]

        if ws.config.get("USE_PYTHON")
            if !ws.config.has_value_for?('python_executable')
                remove_python_shims(ws.root_dir)
                python_bin,_ = auto_resolve_python(ws: ws)
            end

            ws.config.declare 'python_executable', 'string',
                default: "#{python_bin}",
                doc: [ "Select the path to the python executable" ]

            activate_python(ws: ws)
        else
            deactivate_python(ws: ws)
        end
    end
end
