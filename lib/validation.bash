#!/bin/bash
set -euo pipefail

# Configuration validation function
# Returns 0 if validation passes, non-zero if validation fails
function validate_configuration() {
  local api_key="$1"
  local model="$2"
  local trigger="$3"
  local analysis_level="$4"
  local compare_builds="$5"
  local buildkite_api_token="$6"
  local build_log_mode="${7:-all}"

  local errors=0

  # Check required configuration
  if [ -z "${api_key}" ]; then
    echo "❌ Error: api_key is required for Claude Code plugin" >&2
    errors=$((errors + 1))
  fi

  # Validate model format
  if [[ ! "${model}" =~ ^claude- ]]; then
    echo "❌ Error: model must be a valid Claude model starting with 'claude-'" >&2
    errors=$((errors + 1))
  fi

  # Validate trigger
  if [[ ! "${trigger}" =~ ^(on-failure|always|manual)$ ]]; then
    echo "❌ Error: trigger must be one of: on-failure, always, manual. Got: ${trigger}" >&2
    errors=$((errors + 1))
  fi

  # Validate analysis_level
  if [[ ! "${analysis_level}" =~ ^(step|build)$ ]]; then
    echo "❌ Error: analysis_level must be one of: step, build. Got: ${analysis_level}" >&2
    errors=$((errors + 1))
  fi

  # Validate build_log_mode
  if [[ ! "${build_log_mode}" =~ ^(failed|all)$ ]]; then
    echo "❌ Error: build_log_mode must be one of: failed, all. Got: ${build_log_mode}" >&2
    errors=$((errors + 1))
  fi
  
  # Check for Buildkite API token when build level analysis is requested
  if [ "${analysis_level}" = "build" ] && [ "${buildkite_api_token}" = "" ] && [ -z "${BUILDKITE_API_TOKEN:-}" ]; then
    echo "⚠️ Warning: build-level analysis works best with a Buildkite API token" >&2
    echo "   Set buildkite_api_token or ensure BUILDKITE_API_TOKEN environment variable is available" >&2
  fi
  
  # Check for Buildkite API token when build comparison is enabled
  if [ "${compare_builds}" = "true" ] && [ "${buildkite_api_token}" = "" ] && [ -z "${BUILDKITE_API_TOKEN:-}" ]; then
    echo "⚠️ Warning: build comparison requires a Buildkite API token" >&2
    echo "   Set buildkite_api_token or ensure BUILDKITE_API_TOKEN environment variable is available" >&2
  fi
  
  return ${errors}
}

# Check for required tools
# Returns 0 if all tools are available, non-zero otherwise
function validate_tools() {
  local errors=0
  
  # Check for curl
  if ! command -v curl >/dev/null 2>&1; then
    echo "❌ Error: curl is required but not installed" >&2
    errors=$((errors + 1))
  fi
  
  # Check for jq
  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ Error: jq is required but not installed" >&2
    errors=$((errors + 1))
  fi
  
  return ${errors}
}