require "minitest/autorun"
require "tempfile"
require_relative "../fastlane/versioning"

class VersioningTest < Minitest::Test
  def test_keeps_repo_version_when_no_live_version_exists
    assert_equal "1.0.1", OdodokVersioning.next_marketing_version("1.0.1", nil)
  end

  def test_bumps_patch_when_repo_version_matches_live_version
    assert_equal "1.0.1", OdodokVersioning.next_marketing_version("1.0", "1.0")
  end

  def test_bumps_patch_when_repo_version_is_behind_live_version
    assert_equal "1.0.2", OdodokVersioning.next_marketing_version("1.0", "1.0.1")
  end

  def test_keeps_repo_version_when_it_is_ahead_of_live_version
    assert_equal "1.1.0", OdodokVersioning.next_marketing_version("1.1.0", "1.0.1")
  end

  def test_reads_marketing_version_from_xcconfig
    Tempfile.create(["Version", ".xcconfig"]) do |file|
      file.write("MARKETING_VERSION = 9.8.7\n")
      file.flush

      assert_equal "9.8.7", OdodokVersioning.read_marketing_version(file.path)
    end
  end

  def test_reads_marketing_version_when_fastlane_changes_directory
    expected = OdodokVersioning.read_marketing_version("Config/Version.xcconfig")

    Dir.chdir("fastlane") do
      assert_equal expected, OdodokVersioning.read_marketing_version("Config/Version.xcconfig")
    end
  end
end
