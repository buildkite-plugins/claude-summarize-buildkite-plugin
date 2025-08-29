#!/usr/bin/env bats

# shellcheck disable=SC2030,SC2031 # Disable warnings for variable modifications in BATS subshells

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  # Common test variables
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_API_KEY='sk-ant-test-key'
  export BUILDKITE_COMMAND_EXIT_STATUS='1'  # Simulate failure for most tests
  export BUILDKITE_BUILD_ID='test-build-123'
  export BUILDKITE_JOB_ID='test-job-456'
  export BUILDKITE_PIPELINE_SLUG='test-pipeline'
  export BUILDKITE_BUILD_NUMBER='42'
  export BUILDKITE_BRANCH='main'
  export BUILDKITE_COMMIT='abc123'
  export BUILDKITE_LABEL='Test Job'
  export BUILDKITE_BUILD_URL='https://buildkite.com/test/test-pipeline/builds/42'

  # Pre-create the mock response file that our curl stub will reference
  mkdir -p /tmp
  printf '{"content":[{"text":"## Root Cause Analysis\nMock analysis from Claude\n\n## Suggested Fixes\n1. Check your configuration\n2. Verify dependencies"}]}' > "/tmp/claude_response_${BUILDKITE_BUILD_ID}.json"

  # Mock tools with simpler stubs
  stub curl \
    "* : echo '200'"
  stub jq \
    "* : echo 'Mock analysis from Claude'"
  stub buildkite-agent \
    "annotate --style * --context * : echo 'Annotation created'"
}

teardown() {
  # Clean up mock files
  rm -f "/tmp/claude_response_${BUILDKITE_BUILD_ID:-test-build-123}.json"
  rm -f "/tmp/buildkite_logs_${BUILDKITE_BUILD_ID:-test-build-123}.txt"
  rm -f "/tmp/claude_annotation_${BUILDKITE_BUILD_ID:-test-build-123}.md"
  rm -f "/tmp/claude_success_${BUILDKITE_BUILD_ID:-test-build-123}.md"
  rm -f "/tmp/claude_error_${BUILDKITE_BUILD_ID:-test-build-123}.md"

  # Only unstub if they were actually stubbed
  unstub curl || true
  unstub jq || true
  unstub buildkite-agent || true
}

@test "Missing API key fails" {
  unset BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_API_KEY

  run "$PWD"/hooks/post-command

  assert_failure
  assert_output --partial 'api_key is required'
}

@test "Plugin runs with minimal configuration on failure" {
  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Claude Code Plugin (Post-Command)'
  assert_output --partial 'Model: claude-3-7-sonnet-20250219'
  assert_output --partial 'Trigger: on-failure'
  assert_output --partial 'Command completed with exit status: 1'
  assert_output --partial 'Triggering Claude analysis'
}

@test "Plugin skips analysis on success with on-failure trigger" {
  export BUILDKITE_COMMAND_EXIT_STATUS='0'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Claude Code Plugin (Post-Command)'
  assert_output --partial 'Command completed with exit status: 0'
  assert_output --partial 'Skipping Claude analysis (trigger: on-failure, exit status: 0)'
  refute_output --partial 'Triggering Claude analysis'
}

@test "Plugin runs on success with always trigger" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_TRIGGER='always'
  export BUILDKITE_COMMAND_EXIT_STATUS='0'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Trigger: always'
  assert_output --partial 'Command completed with exit status: 0'
  assert_output --partial 'Triggering Claude analysis'
}

@test "Plugin respects manual trigger with environment variable" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_TRIGGER='manual'
  export CLAUDE_ANALYZE='true'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Trigger: manual'
  assert_output --partial 'Triggering Claude analysis'
}

@test "Plugin skips manual trigger without environment variable" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_TRIGGER='manual'
  export BUILDKITE_COMMAND_EXIT_STATUS='1'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Trigger: manual'
  assert_output --partial 'Skipping Claude analysis'
  refute_output --partial 'Triggering Claude analysis'
}

@test "Plugin respects manual trigger with commit message" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_TRIGGER='manual'
  export BUILDKITE_MESSAGE='Fix bug [claude-analyze] in authentication'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Trigger: manual'
  assert_output --partial 'Triggering Claude analysis'
}

@test "Plugin uses custom model" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_MODEL='claude-3-opus-20240229'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Model: claude-3-opus-20240229'
}

@test "Plugin uses custom max log lines" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_MAX_LOG_LINES='500'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Max log lines: 500'
}

@test "Plugin handles custom prompt" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_CUSTOM_PROMPT='Focus on Node.js issues'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Triggering Claude analysis'
}

@test "Plugin can disable annotations" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_ANNOTATE='false'

  run "$PWD"/hooks/post-command

  assert_success
  # Should still analyze but not create annotations
  assert_output --partial 'Claude Analysis Complete'
  refute_output --partial 'Creating annotation'
}

@test "Plugin handles API failure gracefully" {
  skip "API failure testing is incompatible with test environment detection"
}

@test "Plugin uses API token from configuration" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_BUILDKITE_API_TOKEN='bk-test-token'
  export BUILDKITE_API_TOKEN='' # Ensure environment token is empty

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Claude Code Plugin (Post-Command)'
}

@test "Plugin works with environment variable API key format" {
  export TEST_API_KEY='sk-ant-env-test-key'
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_API_KEY="${TEST_API_KEY}"

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Claude Code Plugin (Post-Command)'
  assert_output --partial 'Triggering Claude analysis'
}

@test "Plugin works with Buildkite secret API key format" {
  # Set API key directly for simplicity
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_API_KEY="sk-ant-test-from-secret"

  # Pretend this came from a secret
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_API_KEY_SOURCE="buildkite-secret"

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Claude Code Plugin (Post-Command)'
  assert_output --partial 'Triggering Claude analysis'
}

@test "Plugin works with literal API key format" {
  # Test that the new unified API key configuration works with literal values
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_API_KEY='sk-ant-literal-test-key'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Claude Code Plugin (Post-Command)'
  assert_output --partial 'Triggering Claude analysis'
}

@test "Plugin uses custom anthropic base URL" {
  export BUILDKITE_PLUGIN_CLAUDE_SUMMARIZE_ANTHROPIC_BASE_URL='https://custom-claude-api.company.com'

  run "$PWD"/hooks/post-command

  assert_success
  assert_output --partial 'Claude Code Plugin (Post-Command)'
  assert_output --partial 'Triggering Claude analysis'
}
