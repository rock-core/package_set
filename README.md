# rock.core package set

This installs the Rock toolchain and associated packages. In an
[autoproj](http://rock-robotics.org/documentation/autoproj) bootstrap, this
package set is selected by adding the following in the `package_sets` section
of `autoproj/manifest`:

```
package_sets:
- github: rock-core/package_set
```
## Configuration options

### `cxx_sanitizers` (EXPERIMENTAL)

`cxx_sanitizers` can be set to a comma separated list of sanitizers which will
be passed to gcc's -fsanitize= option, when using the Rock.cmake macro package.
If the list contains 'address', `libasan_path` must also be provided, pointing to
the absolute path to the libasan library.

The configuration is not fine-grained. All programs will run under libasan as
soon as you source `env.sh`. This is heavy-handed, and will probably be refined
in the future.

Because of this, the setup will also disable leak checking. This is because all
programs essentially leak a little and therefore having it on makes
*everything* fails. `git`, `ruby` ... everything.

At least on Ubuntu 20.04, libasan chokes when some C++ code throws exceptions.
This affects the toolchain itself - the build of the toolchain actually does not
pass yet under libasan and Ubuntu 20.04. You have been warned.

## `rubocop-manager`

Rock's model of a single workspace that is managed as a single Bundler
environment works well, but has some drawbacks. In effect, we have to have
the same version of the gem for all packages. This is actually a limitation
of Ruby itself for most of the development, but for CLI-only tooling such
as Rubocop, it is an impediment.

The situation in 2024 was that we, some time during rubocop integration,
fixed the rubocop version to 0.83.0 as rubocop has had a bunch of bugs that
made it fail on rock-core packages. This was left as-is until upgrading
started to become impractical - we would have to upgrade all Rock packages
at once.

Instead, we created `rubocop-manager` (and a workspace alias, `rubocop`).
Packages that need to use rubocop within Rock should call `rubocop-manager`
instead of rubocop, or -- better -- use the `RUBOCOP_CMD` environment variable.
Once this is done, they can write their desired rubocop version in a
`.rubocop-version` file. `rubocop-manager` will auto-install the correct
version and run it.

Note that you **cannot** use `Rubocop::RakeTask` in your Rakefile if you
mean to use this mechanism. Create a plain task and call `rubocop` via
`system`, like this:

```
task "rubocop" do
    system(ENV["RUBOCOP_CMD"] || "rubocop", exception: true)
end
```

If your rubocop environment requires extra gems, you can set up a Gemfile
specifically for the installation of rubocop. Create it in your package set or
in your buildconf, and set the `rubocop-manager-gemfile` configuration variable
accordingly.

## Note for developers of this package set

Part of the Rock behavior is not standard autoproj behavior (flavors, C++11
selection logic, …). Complex logic should be isolated within the `rock/`
folder, and when possible tests should be written in `tests/`

Use `rake test` to run all the tests. To run a single test, one needs to run
from the package set root and add `-I.` to the ruby command line, e.g.

```
ruby -Itest -I. test/cxx11_test.rb
```
