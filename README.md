# Claude Summarize Buildkite Plugin [![Build status](https://badge.buildkite.com/330a0fa71656f6f6c2bedc4812c82021b825bfd7c7125153de.svg)](https://buildkite.com/buildkite/claude-summarize-plugin?branch=main)

AI-powered build analysis and error diagnosis using Claude. This plugin automatically analyzes build failures, provides root cause analysis, and suggests actionable fixes through Buildkite annotations.

## Features

- 🤖 **Intelligent Build Analysis**: Claude analyzes build logs to identify root causes of failures
- 📋 **Buildkite Annotations**: Creates rich annotations with analysis results and suggested fixes
- ⚡ **Smart Triggering**: Configurable triggers (on-failure, always, manual)
- 🔧 **Actionable Insights**: Provides specific steps to resolve issues and prevent future failures
- 🎯 **Context-Aware**: Understands build context including branch, commit, and job information

## Requirements

- **curl**: For API requests
- **jq**: For JSON processing
- **Anthropic API Key**: From [console.anthropic.com](https://console.anthropic.com)

## Quick Start

1. Get your Anthropic API key from [console.anthropic.com](https://console.anthropic.com)
2. Add it to your Buildkite environment variables as `ANTHROPIC_API_KEY`
3. For Buildkite secrets, create `.buildkite/hooks/pre-command` in your repository:
   ```bash
   #!/bin/bash
   export ANTHROPIC_API_KEY=$(buildkite-agent secret get ANTHROPIC_API_KEY)
   export BUILDKITE_API_TOKEN=$(buildkite-agent secret get BUILDKITE_API_TOKEN)
   ```
4. Add the plugin to your pipeline using one of these approaches:

```yaml
steps:
  # Option 1: Using environment variable set at upload time
  - label: "🧪 Run tests"
    command: "npm test"
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"

  # Option 2: Using Buildkite secrets (recommended)
  # First, create .buildkite/hooks/pre-command with:
  # export ANTHROPIC_API_KEY=$(buildkite-agent secret get ANTHROPIC_API_KEY)
  - label: "🧪 More tests"
    command: "npm test"
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"
```

## Configuration Options

### Required

#### `api_key` (string)

Your Anthropic API key for accessing Claude. Use an environment variable reference:

- **Environment variable**: `"${ANTHROPIC_API_KEY}"` - References an environment variable set at upload time
- **Buildkite secrets**: Create `.buildkite/hooks/pre-command` with `export ANTHROPIC_API_KEY=$(buildkite-agent secret get ANTHROPIC_API_KEY)`, then use `"$$ANTHROPIC_API_KEY"` (recommended)

### Optional

#### `anthropic_base_url` (string)

Custom Anthropic API base URL. Default: `https://api.anthropic.com`

Use this to point to alternative endpoints like:
- Enterprise/private Claude deployments
- Proxy servers
- Development/testing environments

#### `model` (string)

Claude model to use for analysis. Default: `claude-3-7-sonnet-20250219`

#### `buildkite_api_token` (string)

Buildkite API token for fetching job logs directly from the Buildkite API. This improves analysis by providing the exact failing job logs. If not specified, the plugin will look for `BUILDKITE_API_TOKEN` in the environment.

#### `trigger` (string)

When to trigger Claude analysis. Options: `on-failure`, `always`, `manual`. Default: `on-failure`

- `on-failure`: Only analyze when the build step fails
- `always`: Analyze every build (success or failure)
- `manual`: Only when `CLAUDE_ANALYZE=true` environment variable is set or commit message contains `[claude-analyze]`

#### `analysis_level` (string)

Level at which to analyze logs. Options: `step`, `build`. These require `buildkite_api_token` to be set in order to fetch job logs, else we default to available environment variables. Default: `step`

- `step`: Analyze only the current step's logs
- `build`: Analyze logs from all jobs in the entire build

#### `max_log_lines` (integer)

Maximum number of log lines to send to Claude for analysis. Default: `1000`

#### `custom_prompt` (string)

Additional context or instructions to include in the analysis prompt.

#### `timeout` (integer)

Timeout in seconds for Claude API requests. Default: `60`

#### `annotate` (boolean)

Whether to create Buildkite annotations with the analysis results. Default: `true`

#### `agent_file` (boolean or string)

Include project context from an agent file in the analysis. Default: `false`

- `true`: Include `AGENT.md` from the repository root
- `false`: Don't include any agent context
- `"path/to/file.md"`: Include the specified file

The agent file should contain project-specific context like architecture details, common issues, coding standards, or troubleshooting guides that help Claude provide more relevant analysis.

#### `compare_builds` (boolean)

Enable build time comparison analysis. When enabled, Claude will analyze build time trends by comparing the current build duration against recent builds. Default: `false`

#### `comparison_range` (integer)

Number of previous builds to compare against for build time analysis. Only used when `compare_builds` is `true`. Default: `5`

## Examples

### Basic Usage - Analyze Failed Tests

```yaml
steps:
  - label: "🧪 Run tests"
    command: "npm test"
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"
```

When tests fail, Claude will analyze the output and create an annotation with:
- Root cause analysis
- Key error explanations
- Suggested fixes
- Prevention strategies

### Build-Level Analysis

```yaml
steps:
  - label: "🔍 Analyze entire build"
    command: "npm test"
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"
          buildkite_api_token: "$$BUILDKITE_API_TOKEN"
          analysis_level: "build"
          trigger: "always"
```

With `analysis_level: "build"`, Claude will analyze logs from all jobs in the build, providing insights across the entire pipeline.

### Always Analyze Builds

```yaml
steps:
  - label: "🏗️ Build application"
    command: "npm run build"
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"
          trigger: "always"
          custom_prompt: "Focus on build performance and optimization opportunities"
```

### Manual Analysis with Custom Context

```yaml
steps:
  - label: "🚀 Deploy to staging"
    command: "./deploy.sh staging"
    env:
      CLAUDE_ANALYZE: "true"  # Trigger manual analysis
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"
          trigger: "manual"
          custom_prompt: "This is a deployment script. Focus on infrastructure and configuration issues."
          max_log_lines: 2000
```

### Build Time Analysis

```yaml
steps:
  - label: "🏗️ Build with performance tracking"
    command: "npm run build"
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"
          compare_builds: true
          comparison_range: 10
          custom_prompt: "Focus on build performance trends and identify any performance regressions"
```

When `compare_builds` is enabled, Claude will:
- Compare current build time against the last N builds (configurable via `comparison_range`)
- Identify performance trends and anomalies
- Suggest optimizations for slow builds
- Highlight significant performance changes

### Multiple Steps with Different Configurations

```yaml
steps:
  - label: "🔍 Lint code"
    command: "npm run lint"
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"
          custom_prompt: "Focus on code quality and style issues"

  - label: "🧪 Run tests"
    command: "npm test"
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"
          custom_prompt: "Focus on test failures and coverage issues"

  - label: "🏗️ Build production"
    command: "npm run build:prod"
    plugins:
      - claude-summarize#v1.1.0:
          api_key: "$$ANTHROPIC_API_KEY"
          trigger: "always"
          custom_prompt: "Focus on build optimization and bundle analysis"
```

## Compatibility

| Elastic Stack | Agent Stack K8s | Hosted (Mac) | Hosted (Linux) | Notes |
| :-----------: | :-------------: | :----------: | :------------: | :---- |
| ✅ | ✅ | ✅ | ✅ |   |

- ✅ Fully compatible assuming requirements are met

## ⚒ Developing

Run tests with

```bash
docker compose run --rm tests
```

## 👩‍💻 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

Please follow the existing code style and include tests for any new features.

## 📜 License

The package is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
