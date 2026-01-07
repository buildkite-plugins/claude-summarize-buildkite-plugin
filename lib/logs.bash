#!/bin/bash
set -euo pipefail

# Helper function to get step-level logs
function get_step_logs() {
  local api_token="$1"
  local max_lines="$2"
  local log_file="$3"

  # Validate parameters
  if [ -z "${api_token}" ] || [ -z "${max_lines}" ] || [ -z "${log_file}" ]; then
    echo "Error: Missing required parameters for get_step_logs" >&2
    return 1
  fi

  local api_url="https://api.buildkite.com/v2/organizations/${BUILDKITE_ORGANIZATION_SLUG}/pipelines/${BUILDKITE_PIPELINE_SLUG}/builds/${BUILDKITE_BUILD_NUMBER}/jobs/${BUILDKITE_JOB_ID}/log"

  if curl -s -f -H "Authorization: Bearer ${api_token}" "${api_url}" > "${log_file}.raw" 2>/dev/null; then
    # Check if the response is JSON and extract content field
    if grep -q '"content":' "${log_file}.raw" 2>/dev/null; then
      if command -v jq >/dev/null 2>&1; then
        # Extract content field from JSON response
        jq -r '.content' "${log_file}.raw" > "${log_file}.content" 2>/dev/null
        if [ -s "${log_file}.content" ]; then
          # Process the extracted content and take last N lines
          tail -n "${max_lines}" "${log_file}.content" > "${log_file}"
          rm -f "${log_file}.raw" "${log_file}.content"
        else
          # Fallback if jq fails to extract content
          tail -n "${max_lines}" "${log_file}.raw" > "${log_file}"
          rm -f "${log_file}.raw" "${log_file}.content"
        fi
      else
        # Fallback if jq is not available
        tail -n "${max_lines}" "${log_file}.raw" > "${log_file}"
        rm -f "${log_file}.raw"
      fi
    else
      # Not JSON or doesn't have content field, just take last N lines
      tail -n "${max_lines}" "${log_file}.raw" > "${log_file}"
      rm -f "${log_file}.raw"
    fi
    return 0
  else
    return 1
  fi
}

# Helper function to get build-level logs (combining multiple jobs)
function get_build_logs_internal() {
  local api_token="$1"
  local max_lines="$2"
  local log_file="$3"
  local build_log_mode="${4:-all}"

  # Validate parameters
  if [ -z "${api_token}" ] || [ -z "${max_lines}" ] || [ -z "${log_file}" ]; then
    echo "Error: Missing required parameters for get_build_logs_internal" >&2
    return 1
  fi

  # First, get the build to find all jobs
  local build_url="https://api.buildkite.com/v2/organizations/${BUILDKITE_ORGANIZATION_SLUG}/pipelines/${BUILDKITE_PIPELINE_SLUG}/builds/${BUILDKITE_BUILD_NUMBER}"
  local build_data_file="/tmp/build_${BUILDKITE_BUILD_ID}.json"

  if curl -s -f -H "Authorization: Bearer ${api_token}" "${build_url}" > "${build_data_file}" 2>/dev/null; then
    # Extract job IDs from the build based on build_log_mode
    if command -v jq >/dev/null 2>&1; then
      local job_ids

      if [ "${build_log_mode}" = "failed" ]; then
        # Filter for jobs with non-zero exit_status (failed jobs only)
        job_ids=$(jq -r '.jobs[] | select(.exit_status != null and .exit_status != 0) | .id' "${build_data_file}" 2>/dev/null)

        # If no failed jobs found, fall back to getting all completed jobs
        if [ -z "${job_ids}" ]; then
          job_ids=$(jq -r '.jobs[] | select(.exit_status != null) | .id' "${build_data_file}" 2>/dev/null)
        fi
      else
        job_ids=$(jq -r '.jobs[].id' "${build_data_file}" 2>/dev/null)
      fi

      if [ -n "${job_ids}" ]; then
        # Create a combined log file
        : > "${log_file}"

        # Add a summary header showing all jobs and their status
        {
          echo "========================================"
          echo "BUILD JOBS SUMMARY"
          echo "========================================"
          jq -r '.jobs[] | "- \(.name // "Unnamed job"): exit_status=\(.exit_status // "pending"), state=\(.state // "unknown")"' "${build_data_file}" 2>/dev/null
          echo ""
          if [ "${build_log_mode}" = "failed" ]; then
            echo "Note: Fetching detailed logs only for FAILED jobs to reduce token usage."
          else
            echo "Note: Fetching detailed logs for ALL completed jobs."
          fi
          echo ""
        } >> "${log_file}"

        # Process each job
        local job_count=0
        for job_id in ${job_ids}; do  # Word splitting is intentional here
          local job_log_file="/tmp/job_${job_id}_logs.txt"
          local job_url="https://api.buildkite.com/v2/organizations/${BUILDKITE_ORGANIZATION_SLUG}/pipelines/${BUILDKITE_PIPELINE_SLUG}/builds/${BUILDKITE_BUILD_NUMBER}/jobs/${job_id}/log"

          # Get job details for header
          local job_details_url="https://api.buildkite.com/v2/organizations/${BUILDKITE_ORGANIZATION_SLUG}/pipelines/${BUILDKITE_PIPELINE_SLUG}/builds/${BUILDKITE_BUILD_NUMBER}/jobs/${job_id}"
          local job_name="Job ${job_id}"

          if curl -s -f -H "Authorization: Bearer ${api_token}" "${job_details_url}" > "/tmp/job_${job_id}_details.json" 2>/dev/null; then
            if command -v jq >/dev/null 2>&1; then
              job_name=$(jq -r '.name // "Job '"${job_id}"'"' "/tmp/job_${job_id}_details.json" 2>/dev/null)
            fi
          fi

          # Add a separator for this job
          { printf "\n========================================"; echo "JOB: ${job_name} (${job_id})"; printf "========================================\n"; } >> "${log_file}"

          # Fetch this job's logs
          if curl -s -f -H "Authorization: Bearer ${api_token}" "${job_url}" > "${job_log_file}.raw" 2>/dev/null; then
            process_job_log "${job_log_file}.raw" "${job_log_file}" "${max_lines}" "${log_file}"
            job_count=$((job_count + 1))
          else
            echo "Could not fetch logs for this job." >> "${log_file}"
          fi

          rm -f "/tmp/job_${job_id}_details.json"
        done

        if [ "${job_count}" -gt 0 ]; then
          return 0
        fi
      fi
    fi

    rm -f "${build_data_file}"
  fi

  return 1
}

# Helper function to process a job log
function process_job_log() {
  local raw_log_file="$1"
  local output_log_file="$2"
  local max_lines="$3"
  local combined_log_file="$4"

  # Process the log similar to the step-level function
  if grep -q '"content":' "${raw_log_file}" 2>/dev/null; then
    if command -v jq >/dev/null 2>&1; then
      jq -r '.content' "${raw_log_file}" > "${output_log_file}" 2>/dev/null
      if [ ! -s "${output_log_file}" ]; then
        # Fallback if jq fails
        cat "${raw_log_file}" > "${output_log_file}"
      fi
    else
      # Fallback if jq is not available
      cat "${raw_log_file}" > "${output_log_file}"
    fi
  else
    # Not JSON, use as is
    cat "${raw_log_file}" > "${output_log_file}"
  fi

  # Append logs to the combined file (last N lines)
  if [ -s "${output_log_file}" ]; then
    # Calculate lines per job based on the total max and job count
    # For simplicity we'll use max_lines/10 lines per job with a minimum of 100
    local lines_per_job=$((max_lines / 10))
    if [ "${lines_per_job}" -lt 100 ]; then
      lines_per_job=100
    fi

    tail -n "${lines_per_job}" "${output_log_file}" >> "${combined_log_file}"
  fi

  # Clean up
  rm -f "${raw_log_file}" "${output_log_file}"
}

# Get logs from common system locations
function get_system_logs() {
  local max_lines="$1"
  local log_file="$2"

  local potential_logs=(
    "/tmp/buildkite-agent.log"
    "${BUILDKITE_BUILD_CHECKOUT_PATH:-/tmp}/buildkite.log"
    "/var/log/buildkite-agent/buildkite-agent.log"
    "${HOME}/.buildkite-agent/buildkite-agent.log"
    "/opt/homebrew/var/log/buildkite-agent.log"
  )

  # Try journalctl for systems using systemd
  if command -v journalctl >/dev/null 2>&1; then
    if journalctl -u buildkite-agent -n "${max_lines}" > "${log_file}.journal" 2>/dev/null; then
      if [ -s "${log_file}.journal" ]; then
        mv "${log_file}.journal" "${log_file}"
        return 0
      fi
      rm -f "${log_file}.journal"
    fi
  fi

  for log_path in "${potential_logs[@]}"; do
    if [ -f "${log_path}" ] && [ -r "${log_path}" ]; then
      tail -n "${max_lines}" "${log_path}" > "${log_file}" 2>/dev/null
      if [ -s "${log_file}" ]; then
        return 0
      fi
    fi
  done

  return 1
}

# Create a fallback log with basic build information
function create_fallback_log() {
  local log_file="$1"

  {
    echo "Build Information Summary:"
    echo "- Pipeline: ${BUILDKITE_PIPELINE_SLUG:-Unknown}"
    echo "- Build: #${BUILDKITE_BUILD_NUMBER:-Unknown}"
    echo "- Job: ${BUILDKITE_LABEL:-Unknown}"
    echo "- Branch: ${BUILDKITE_BRANCH:-Unknown}"
    echo "- Commit: ${BUILDKITE_COMMIT:-Unknown}"
    echo "- Exit Status: ${BUILDKITE_COMMAND_EXIT_STATUS:-Unknown}"
    echo "- Build URL: ${BUILDKITE_BUILD_URL:-Unknown}"
    echo ""
    echo "Note: Detailed logs could not be retrieved. This may be due to:"
    echo "- Missing BUILDKITE_API_TOKEN environment variable"
    echo "- Insufficient permissions to access logs"
    echo "- Log files not available in expected locations"
    echo ""
    echo "To improve log analysis, ensure:"
    echo "1. BUILDKITE_API_TOKEN is set with appropriate permissions"
    echo "2. The buildkite-agent has access to log files"
    echo "3. The plugin runs in the same environment as the failed command"
  } > "${log_file}"

  return 0
}

# Create agent environment info log
function create_agent_environment_log() {
  local log_file="$1"

  # Create a basic log using Buildkite environment variables
  {
    echo "Build Information from Agent Environment:"
    echo "- Pipeline: ${BUILDKITE_PIPELINE_SLUG:-Unknown}"
    echo "- Build: #${BUILDKITE_BUILD_NUMBER:-Unknown}"
    echo "- Job: ${BUILDKITE_LABEL:-Unknown}"
    echo "- Branch: ${BUILDKITE_BRANCH:-Unknown}"
    echo "- Commit: ${BUILDKITE_COMMIT:-Unknown}"
    echo "- Exit Status: ${BUILDKITE_COMMAND_EXIT_STATUS:-Unknown}"
    echo "- Command: ${BUILDKITE_COMMAND:-Unknown}"
    echo "- Working Directory: $(pwd)"
    echo ""
    echo "Note: Step logs cannot be directly accessed via buildkite-agent."
  } > "${log_file}"

  if [ -s "${log_file}" ]; then
    return 0
  fi

  return 1
}

# Main function to get logs based on analysis level
function fetch_build_logs() {
  local api_token="$1"
  local max_lines="$2"
  local analysis_level="$3"
  local build_log_mode="${4:-all}"

  # Validate parameters
  if [ -z "${max_lines}" ] || [ -z "${analysis_level}" ]; then
    echo "Error: Missing required parameters for fetch_build_logs" >&2
    return 1
  fi

  # Ensure we have a valid build ID for the temp file
  local build_id="${BUILDKITE_BUILD_ID:-unknown}"
  local log_file="/tmp/buildkite_logs_${build_id}.txt"

  # Ensure log file can be created
  if ! touch "${log_file}" 2>/dev/null; then
    echo "Error: Cannot create log file at ${log_file}" >&2
    return 1
  fi

  # For build-level analysis, try to get all jobs in the build
  if [ "${analysis_level}" = "build" ]; then
    if [ -n "${api_token}" ]; then
      if get_build_logs_internal "${api_token}" "${max_lines}" "${log_file}" "${build_log_mode}"; then
        echo "${log_file}"
        return 0
      fi
    fi
  fi

  # Method 1: Try Buildkite API if token and job ID are available (step-level analysis)
  if [ -n "${api_token}" ] && [ -n "${BUILDKITE_JOB_ID:-}" ]; then
    if get_step_logs "${api_token}" "${max_lines}" "${log_file}"; then
      echo "${log_file}"
      return 0
    fi
  fi

  # Method 2: Try to use Buildkite agent env vars for basic information
  if command -v buildkite-agent >/dev/null 2>&1; then
    if create_agent_environment_log "${log_file}"; then
      echo "${log_file}"
      return 0
    fi
  fi

  # Method 3: Try to read from common log locations
  if get_system_logs "${max_lines}" "${log_file}"; then
    echo "${log_file}"
    return 0
  fi

  # Method 4: Fallback - create a basic log with available information
  if create_fallback_log "${log_file}"; then
    echo "${log_file}"
    return 0
  else
    echo "Error: Failed to create fallback log" >&2
    return 1
  fi
}
