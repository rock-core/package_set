require 'test_helpers'
require 'rock/python'
require 'autoproj/test'
require 'flexmock'

module Rock
    describe "activate_python" do
        before do
            @pkg = Autobuild::Package.new
            @ws = ws_create
            flexmock(@pkg)
            @pkg.prefix = "/tmp/install/foo/"
            @env = flexmock(base: Autobuild::Environment)

            @test_python = File.join(Dir.tmpdir(), "test-python")
            if !File.exist?(@test_python)
                File.symlink("/usr/bin/python",
                             @test_python)
            end
        end
        after do
            if !File.exist?(@test_python)
                File.rm(@test_python)
            end
        end

        it "does get the python version" do
            assert_raises { Rock.get_python_version("no-existing-file") }
            assert_raises { Rock.get_python_version(__FILE__) }

            assert(Rock.get_python_version("/usr/bin/python") != "")
        end

        it "does validate the python version" do
            version, valid = Rock.validate_python_version("/usr/bin/python",nil)
            assert(version =~ /[0-9]+\.[0-9]+/)
            assert(valid)

            version_a, valid = Rock.validate_python_version("/usr/bin/python", ">2.0")
            assert(version_a == version)
            assert(valid)

            version_a, valid = Rock.validate_python_version("/usr/bin/python", "<100.0")
            assert(version_a == version)
            assert(valid)

            version_a, valid = Rock.validate_python_version("/usr/bin/python", ">100.0")
            assert(version_a == version)
            assert(!valid)
        end

        it "does find python" do
            assert_raises { Rock.find_python(ws: @ws, version: ">100.0" ) }
            python_bin, version = Rock.find_python(ws: @ws, version: "<100.0" )
            assert(File.exist?(python_bin))
            assert(version =~ /[0-9]+\.[0-9]+/)

            # Python3 has higher priority, so should be picked
            python_path = `which python3`.strip()
            if File.exist?(python_path)
                assert(version =~ /3.[0-9]+/)
            end
        end

        it "custom resolve python" do
            python_bin_resolved, version_resolved = Rock.custom_resolve_python(ws: @ws,
                                                                              bin: @test_python)
            assert(python_bin_resolved)
            assert_raises { Rock.custom_resolve_python(ws: @ws,
                                                       bin: @test_python,
                                                       version: ">100.0") }

            assert_raises { Rock.custom_resolve_python(ws: @ws,
                                                      bin: "no-existing-python") }


            python_bin, version = Rock.find_python(ws: @ws)
            @ws.config.set("python_executable", @test_python)
            @ws.config.set("python_version", version)

            python_bin_resolved, version_resolved = Rock.resolve_python(ws: @ws)
            assert(python_bin_resolved == @test_python)
            assert(version_resolved == version)

            assert_raises { Rock.resolve_python(ws: @ws, version: ">100.0") }

            @ws.config.set("python_executable", nil)
            @ws.config.set("python_version", nil)
        end

        it "does update the python path" do
            python_bin = `which python`.strip()
            assert($? == 0, "This test requires python to be available on your"\
                   " system, so please install before running this test")

            @ws.config.set("USE_PYTHON",true)
            bin, version, sitelib_path = Rock.activate_python_path(@pkg, ws: @ws)

            assert(python_bin == bin)
            assert(version == Rock.get_python_version(python_bin))
            assert(sitelib_path == File.join(@pkg.prefix, "lib","python#{version}","site-packages"))

            found_path = false
            path_pattern = File.join(@pkg.prefix,"lib","python.*","site-packages")

            @env.should_receive(:add_path)
            op = @pkg.apply_env(@env).first

            assert(op.type == :add_path)
            assert(op.name == "PYTHONPATH")
            op.values.each do |p|
                if p =~ /#{path_pattern}/
                    found_path = true
                end
            end
            assert(found_path)
            assert(!@ws.config.has_value_for?('python_executable'))
            assert(!@ws.config.has_value_for?('python_version'))

            assert_raises { Rock.activate_python_path(@pkg, ws: @ws, version: ">100.0") }

            Autobuild.programs["python"] = "no-existing-executable"
            assert_raises { Rock.activate_python_path(@pkg, ws: @ws, version: ">100.0") }
            Autobuild.programs["python"] = nil
        end

        it "does not update python path" do
            @ws.config.reset
            @ws.config.set('interactive',false)
            @ws.config.set('USE_PYTHON',false)

            pkg = flexmock('testpkg')
            prefix = File.join(@ws.root_dir,"install","testpkg")
            pkg.should_receive(:prefix).and_return(prefix)
            assert(!@ws.config.has_value_for?('python_executable'))
            assert(!@ws.config.has_value_for?('python_version'))

            bin,version,path = Rock.activate_python_path(pkg)
            assert(!(bin || version || path))
        end

        it "does activate_python" do
            Rock.activate_python(ws: @ws)
            assert(@ws.config.has_value_for?('python_executable'))
            assert(@ws.config.has_value_for?('python_version'))

            python_bin = File.join(@ws.root_dir, "install","bin","python")
            assert(File.exist?(python_bin))
            python_version = Rock.get_python_version(python_bin)
            assert(python_version == @ws.config.get('python_version'))

            pip_bin = File.join(@ws.root_dir, "install","bin","pip")
            assert(File.exist?(pip_bin))
            pip_version = Rock.get_pip_version(pip_bin)
            expected_pip_version = `#{python_bin} -c "import pip; print(pip.__version__)"`.strip
            assert(pip_version == expected_pip_version)
        end

        it "does setup python" do
            @ws.config.reset
            @ws.config.set('interactive',false)
            @ws.config.set('USE_PYTHON',true)
            Rock.setup_python_configuration_options(ws: @ws)
            assert(@ws.config.get('USE_PYTHON'))
            assert(@ws.config.get('python_executable'))
            assert(@ws.config.get('python_version'))

            @ws.config.reset
            @ws.config.set('interactive',false)
            Rock.setup_python_configuration_options(ws: @ws)
            if Autoproj::VERSION > '2.11.0'
                assert(!@ws.config.get('USE_PYTHON'))
            else
                assert(@ws.config.get('USE_PYTHON') == 'no')
            end
            assert(!@ws.config.has_value_for?('python_executable'))
            assert(!@ws.config.has_value_for?('python_version'))
        end
    end
end
