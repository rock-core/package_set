# Wrappers used if autoproj itself supports python venvs (see rock/python.rb)
#
# Autoproj::Python supersedes the python support of this package set. The Rock
# functions are kept for backward compatibility and delegate to it.
require 'set'

module Rock
    def self.python_deprecation_warning(name, replacement)
        @python_deprecation_warnings ||= Set.new
        return unless @python_deprecation_warnings.add?(name)

        Autoproj.warn "Rock.#{name} is deprecated, #{replacement}"
    end

    %i[get_python_version get_pip_version validate_version validate_python_version
       find_python get_python_from_config custom_resolve_python auto_resolve_python
       resolve_python remove_python_shims remove_pip_shims rewrite_python_shims
       rewrite_pip_shims activate_python deactivate_python activate_python_path
       assert_python_activated setup_python_configuration_options].each do |name|
        define_singleton_method(name) do |*args, **kw, &block|
            python_deprecation_warning(name, "use Autoproj::Python.#{name} instead")
            Autoproj::Python.send(name, *args, **kw, &block)
        end
    end

    def self.get_python_from_bootstrap(ws: Autoproj.workspace, version: nil)
        python_deprecation_warning(
            :get_python_from_bootstrap, "use Autoproj::Python.get_python_from_config instead"
        )
        Autoproj::Python.get_python_from_config(ws: ws, version: version)
    end

    # The venv is created and activated by autoproj itself
    %i[check_init_venv create_venv disable_venv activate_python_venv].each do |name|
        define_singleton_method(name) do |*_args, **_kw|
            python_deprecation_warning(name, "autoproj manages the python venv itself")
            nil
        end
    end
end
