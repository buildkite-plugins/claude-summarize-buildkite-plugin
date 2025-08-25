#!/bin/bash
set -euo pipefail

# Configuration validation function
# Returns 0 if validation passes, non-zero if validation fails
function validate_configuration() {
  local api_key="$1"
  local bedrock="$2"
  local model="$3"
  local trigger="$4"
  local analysis_level="$5"
  local compare_builds="$6"
  local buildkite_api_token="$7"
  
  local errors=0
  
  # Check required configuration
  # Skip API key check if using Bedrock (which uses AWS credentials)
  if [ -z "${api_key}" ] && [ "${bedrock}" != "true" ]; then
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