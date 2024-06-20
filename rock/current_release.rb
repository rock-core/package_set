module Rock
    # Whether this checkout is tracking a release
    def self.in_release?
        File.exist?(File.join(Autoproj.root_dir, "autoproj", "overrides.d", "25-release.yml"))
    end
end
