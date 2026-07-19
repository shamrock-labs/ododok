# frozen_string_literal: true

require "minitest/autorun"

class DistributionContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def setup
    @project = File.read(File.join(ROOT, "Project.swift"))
    @fastfile = File.read(File.join(ROOT, "fastlane/Fastfile"))
  end

  def test_testflight_uses_production_backend
    settings = @project.match(/testFlight:\s*\[(.*?)\]\.merging/m)&.[](1)

    refute_nil settings, "TestFlight build settings must exist"
    assert_includes settings, '"BACKEND_BASE_URL": "https://api.ododok.cloud"'
    assert_includes settings, '"APP_RUNTIME_ENVIRONMENT": "prod"'
    refute_includes settings, "api.dev.ododok.cloud"
  end

  def test_app_store_upload_waits_for_manual_review_submission
    release_lane = @fastfile.match(/lane :release do(.*?)^  end$/m)&.[](1)

    refute_nil release_lane, "release lane must exist"
    assert_includes release_lane, "submit_for_review: false"
    assert_includes release_lane, "automatic_release: false"
    refute_includes release_lane, "submit_for_review: true"
  end
end
