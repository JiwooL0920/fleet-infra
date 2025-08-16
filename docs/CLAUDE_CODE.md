# CLAUDE_CODE.md

A comprehensive guide to using Claude Code effectively for development, specifically tailored for this Kubernetes GitOps infrastructure project.

## Quick Start

### Installation & Setup
```bash
# Start Claude Code in project directory
cd /path/to/fleet-infra
claude

# Start with specific query
claude "Help me understand the Flux deployment structure"

# Continue previous conversation
claude -c

# Query and exit (non-interactive)
claude -p "Check if Traefik is running properly"
```

## Essential CLI Commands

### Basic Commands
```bash
claude                    # Start interactive REPL
claude "query"           # Start REPL with initial prompt
claude -p "query"        # Query via SDK and exit (no interaction)
claude -c                # Continue most recent conversation
claude --resume <id>     # Resume specific session
claude update            # Update to latest version
claude mcp               # Configure Model Context Protocol servers
```

### CLI Flags & Options
```bash
--add-dir <path>         # Add working directories
--allowedTools <tools>   # Specify allowed tools (comma-separated)
--print/-p              # Print response without interactive mode
--output-format <format> # Set output format (text/json/stream-json)
--verbose               # Enable detailed logging
--model <model>         # Set session model
--permission-mode <mode> # Begin in specific permission mode
--continue              # Load most recent conversation
```

### Output Formats for Automation
```bash
# JSON output for scripting
claude -p "Get Flux status" --output-format json

# Stream JSON for real-time processing
claude --output-format stream-json
```

## Interactive Mode Commands

### Built-in Slash Commands
```bash
/add-dir <path>         # Add working directories to context
/clear                  # Clear conversation history
/help                   # Get usage help and available commands
/model                  # Select or change AI model
/review                 # Request code review of recent changes
/memory                 # Edit CLAUDE.md memory files
/init                   # Initialize project with CLAUDE.md guide
/vim                    # Enable vim mode for input editing
/terminal-setup         # Configure terminal for better experience
```

### Quick Input Methods
```bash
#                       # Memory shortcut - references CLAUDE.md
/                       # Invoke slash command
\                       # Line continuation (multiline input)
```

### Keyboard Shortcuts
```bash
Ctrl+C                  # Cancel current input or generation
Ctrl+D                  # Exit Claude Code session
Ctrl+L                  # Clear terminal screen
Ctrl+R                  # Reverse search command history
Up/Down arrows          # Navigate command history
Esc + Esc              # Edit previous message
Option+Enter (macOS)    # Multiline input
Shift+Enter            # Multiline input (after /terminal-setup)
```

### Vim Mode (after `/vim`)
```bash
h/j/k/l                # Navigate (left/down/up/right)
i                      # Enter INSERT mode
ESC                    # Enter NORMAL mode
:w                     # Write/save
:q                     # Quit
```

## Project-Specific Workflows

### Infrastructure Management
```bash
# Understanding the deployment structure
"Explain the wave-based deployment architecture"
"How do service dependencies work in this project?"
"Show me the difference between dev and prod environments"

# Troubleshooting deployments
"Why is the Traefik HelmRelease failing?"
"Check the status of all PostgreSQL resources"
"Investigate External Secrets synchronization issues"

# Making changes
"Help me add a new service to the infrastructure"
"Update the PostgreSQL cluster configuration for better performance"
"Create environment-specific overrides for the monitoring stack"
```

### Kubernetes Operations
```bash
# Quick status checks
"Check if all Flux kustomizations are ready"
"Show me the health of all database services"
"Get the current status of External Secrets"

# Debugging specific issues
"Why are pods in cnpg-system namespace failing?"
"Check LocalStack connectivity and health"
"Investigate Redis authentication issues"

# Configuration management
"Show me how cluster-vars-patch.yaml works"
"Explain the External Secrets ClusterSecretStore configuration"
"Help me understand the Flux source and kustomization relationships"
```

### Local Development
```bash
# Setup and initialization
"Walk me through the local development setup process"
"Help me initialize AWS secrets in LocalStack"
"Explain the port forwarding setup for all services"

# Testing and validation
"How do I test Flux changes before committing?"
"Show me how to verify service startup order"
"Help me debug External Secrets synchronization locally"
```

## Advanced Features

### Working with Files and Directories
```bash
# File references
"Check the configuration in apps/base/traefik/"
"Compare dev and prod cluster-vars-patch.yaml files"
"Show me all Redis-related configurations"

# Directory analysis
"Analyze the base/ directory structure"
"Review all HelmRelease files for common patterns"
"Find all External Secret configurations"
```

### Code Review and Analysis
```bash
/review                 # Automatic code review of recent changes
"Review this PR for Kubernetes best practices"
"Analyze the security implications of these External Secret changes"
"Check if the new service follows our deployment patterns"
```

### Extended Thinking for Complex Tasks
```bash
# Complex problem-solving
"Design a disaster recovery strategy for this infrastructure"
"Plan a migration from the current PostgreSQL setup to a new version"
"Architect a multi-region deployment strategy"

# Comprehensive analysis
"Perform a complete security audit of the current setup"
"Analyze the performance characteristics of our deployment waves"
"Design a comprehensive monitoring and alerting strategy"
```

### Working with Images and Screenshots
```bash
# Paste or reference images directly
"Analyze this Grafana dashboard screenshot"
"What does this Kubernetes error message mean?" [with screenshot]
"Review this architecture diagram for improvements"
```

## Configuration and Customization

### Project Settings (`.claude/settings.json`)
```json
{
  "allowedTools": ["Bash", "Edit", "Read", "Write", "Glob", "Grep"],
  "environmentVariables": {
    "KUBECONFIG": "./kubeconfig"
  },
  "hooks": {
    "pre-edit": "echo 'Making changes to kubernetes config'"
  }
}
```

### Personal Settings (`.claude/settings.local.json`)
```json
{
  "model": "claude-3-5-sonnet-20241022",
  "verbose": true,
  "defaultPermissionMode": "ask"
}
```

### Custom Slash Commands (`.claude/commands/`)
Create custom commands for your project:

```bash
# .claude/commands/flux-status.txt
Check the status of all Flux resources:
- flux get all
- Show any failed reconciliations
- Provide troubleshooting guidance if issues found
```

```bash
# .claude/commands/db-health.txt
Check database health:
- PostgreSQL cluster status in cnpg-system
- Redis connectivity and authentication
- External Secrets synchronization status
- Database backup status
```

## Best Practices for This Project

### Starting a Session
1. **Begin with context**: `claude` in the project root
2. **Set the scope**: "I'm working on [specific component/issue]"
3. **Provide background**: Reference the specific environment (dev/prod)

### Effective Prompting
```bash
# Good - Specific and contextual
"The Traefik HelmRelease in the dev environment is failing to reconcile. Check the status and help me debug the issue."

# Better - Includes relevant context
"I'm seeing Traefik reconciliation failures after updating the cluster-vars-patch.yaml in the dev environment. The change was meant to update the LoadBalancer configuration. Help me investigate."

# Best - Comprehensive context with specific goals
"Context: I updated the Traefik LoadBalancer configuration in clusters/stages/dev/clusters/services-amer/cluster-vars-patch.yaml to change the external IP range. Now the HelmRelease is failing to reconcile. Goal: Debug the issue, fix the configuration, and ensure the change deploys successfully. Please start by checking the current Flux status."
```

### Managing Complex Tasks
1. **Use /memory** to update CLAUDE.md with new information
2. **Break down complex changes** into multiple focused sessions
3. **Resume conversations** with `claude -c` for ongoing work
4. **Use extended thinking** for architectural decisions

### Collaboration Workflows
```bash
# Preparing for team review
/review                 # Get automated code review
"Prepare a summary of changes for the team review"
"Generate documentation for the new service deployment"

# Knowledge sharing
"Document the External Secrets setup process for the team"
"Create troubleshooting guides for common Flux issues"
"Explain the wave-based deployment strategy for new team members"
```

### Safety and Validation
```bash
# Before making changes
"Validate this configuration change against Kubernetes best practices"
"Check if this change will affect other services"
"Simulate the deployment impact"

# Testing changes
"Help me create a test plan for this infrastructure change"
"Guide me through validating the External Secrets configuration"
"Show me how to verify the deployment wave dependencies"
```

## Troubleshooting Claude Code

### Common Issues
```bash
# Permission issues
claude --permission-mode ask    # Start with permission prompts
claude --allowedTools Bash,Read,Edit  # Limit tools if needed

# Performance issues
claude --verbose               # Enable detailed logging
/clear                        # Clear conversation history

# Context issues
/add-dir <path>               # Add missing directories
#                             # Reference CLAUDE.md for context
```

### Configuration Problems
```bash
# Check current settings
claude config list

# Reset configuration
claude config reset

# Update settings
claude config set model claude-3-5-sonnet-20241022
```

## Integration with Development Tools

### Git Workflows
```bash
# Before committing
"Review my staged changes for this Flux configuration update"
"Check if the commit message follows our conventions"
"Validate that environment-specific files are correct"

# After changes
"Help me create a comprehensive PR description"
"Generate release notes for this infrastructure update"
"Create documentation for the new deployment process"
```

### Kubernetes Integration
```bash
# Direct kubectl integration
"Run kubectl get pods --all-namespaces and explain any issues"
"Check the Flux reconciliation status and help me understand any failures"
"Analyze the External Secrets logs for synchronization problems"

# Helm and Flux integration
"Validate this HelmRelease configuration"
"Check if the Flux source is up to date"
"Help me understand why this kustomization is not applying"
```

### Monitoring and Observability
```bash
# Using port forwarding effectively
"Start port forwarding and help me access Grafana dashboards"
"Connect to pgAdmin4 and show me how to verify database health"
"Access the Temporal UI and explain the workflow status"

# Log analysis
"Analyze the PostgreSQL operator logs for cluster creation issues"
"Check External Secrets Operator logs for authentication problems"
"Review Traefik logs for ingress configuration issues"
```

## Tips for Maximum Productivity

### Session Management
- **Use descriptive sessions**: Start each major task in a new session
- **Resume strategically**: Use `claude -c` for ongoing complex work
- **Clean slate approach**: Use `/clear` when switching between unrelated tasks

### Context Management
- **Reference files explicitly**: "Check the configuration in apps/base/postgresql/"
- **Use working directories**: `/add-dir` for multi-project work
- **Leverage memory**: Update CLAUDE.md with `/memory` for team knowledge

### Automation Integration
- **Script common queries**: Use `--output-format json` for automation
- **Create custom commands**: Build project-specific slash commands
- **Use hooks**: Automate pre/post actions with configuration hooks

### Knowledge Building
- **Document learnings**: Update CLAUDE.md after solving complex issues
- **Share insights**: Create team-specific custom commands
- **Build troubleshooting guides**: Document common problem-solution patterns

This guide provides a comprehensive foundation for using Claude Code effectively with this Kubernetes GitOps infrastructure project. Regular updates to both this guide and CLAUDE.md will help maintain project knowledge and improve team productivity.