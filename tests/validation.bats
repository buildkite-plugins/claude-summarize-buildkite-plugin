#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  # Common test variables
  export BUILDKITE_BUILD_ID='test-build-123'
  export BUILDKITE_JOB_ID='test-job-456'
  export BUILDKITE_PIPELINE_SLUG='test-pipeline'

  # Load validation functions
  source "$PWD/lib/validation.bash"
}

@test "Validate configuration succeeds with valid inputs" {
  run validate_configuration "sk-ant-test-key" "claude-3-opus" "on-failure" "step" "false" ""

  assert_success
  refute_output --partial "Error"
}

@test "Validate configuration fails with missing API key" {
  run validate_configuration "" "claude-3-opus" "on-failure" "step" "false" ""

  assert_failure
  assert_output --partial "Error: api_key is required"
}

@test "Validate configuration fails with invalid model" {
  run validate_configuration "sk-ant-test-key" "not-claude" "on-failure" "step" "false" ""

  assert_failure
  assert_output --partial "Error: model must be a valid Claude model"
}

@test "Validate configuration fails with invalid trigger" {
  run validate_configuration "sk-ant-test-key" "claude-3-opus" "invalid-trigger" "step" "false" ""

  assert_failure
  assert_output --partial "Error: trigger must be one of: on-failure, always, manual"
}

@test "Validate configuration fails with invalid analysis level" {
  run validate_configuration "sk-ant-test-key" "claude-3-opus" "on-failure" "invalid-level" "false" ""

  assert_failure
  assert_output --partial "Error: analysis_level must be one of: step, build"
}

@test "Validate configuration warns about missing API token for build level" {
  run validate_configuration "sk-ant-test-key" "claude-3-opus" "on-failure" "build" "false" ""

  assert_success
  assert_output --partial "Warning: build-level analysis works best with a Buildkite API token"
}

@test "Validate configuration warns about missing API token for build comparison" {
  run validate_configuration "sk-ant-test-key" "claude-3-opus" "on-failure" "step" "true" ""

  assert_success
  assert_output --partial "Warning: build comparison requires a Buildkite API token"
}

@test "Validate tools succeeds with available tools" {
  # Mock commands
  # shellcheck disable=SC2329  # Mock command for BATS test; intentional redefinition
  command() {
    return 0
  }

  run validate_tools

  assert_success
  refute_output --partial "Error"
}

@test "Validate tools fails when curl is missing" {
  # Mock commands
  # shellcheck disable=SC2329  # Mock command for BATS test; intentional redefinition
  command() {
    if [[ "$*" == *"curl"* ]]; then
      return 1
    fi
    return 0
  }

  run validate_tools

  assert_failure
  assert_output --partial "Error: curl is required"
}

@test "Validate tools fails when jq is missing" {
  # Mock commands
  # shellcheck disable=SC2317
  command() {
    if [[ "$*" == *"jq"* ]]; then
      return 1
    fi
    return 0
  }

  run validate_tools

  assert_failure
  assert_output --partial "Error: jq is required"
}
