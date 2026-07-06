require "rubygems"

module OdodokVersioning
  module_function

  def read_marketing_version(path)
    line = File.readlines(path).find { |candidate| candidate.match?(/^\s*MARKETING_VERSION\s*=/) }
    raise "MARKETING_VERSION not found in #{path}" unless line

    line.split("=", 2).last.strip
  end

  def next_marketing_version(repo_version, live_version)
    return repo_version if live_version.nil? || live_version.empty?
    return repo_version if Gem::Version.new(repo_version) > Gem::Version.new(live_version)

    bump_patch(live_version)
  end

  def bump_patch(version)
    parts = version.split(".").map(&:to_i)
    parts << 0 while parts.length < 3
    parts[2] += 1
    parts.join(".")
  end
end
