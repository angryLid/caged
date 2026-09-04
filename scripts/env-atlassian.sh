#!/bin/sh
# caged: map the shared ATLASSIAN_* env trio the operator injects
# (ATLASSIAN_HOST / ATLASSIAN_EMAIL / ATLASSIAN_API_TOKEN) onto the env vars
# the Atlassian CLIs actually read:
#   cfl  (Confluence)  -> CFL_URL / CFL_EMAIL / CFL_API_TOKEN
#   jira (jira-cli)    -> JIRA_SERVER / JIRA_LOGIN / JIRA_API_TOKEN
# Sourced from every image entrypoint (pi/dsh/cmdc) before the agent
# launches, so the assignment happens INSIDE the container regardless of how
# it was started. CLI-specific vars win when already set; ATLASSIAN_URL is
# honored as a legacy alias for the site URL. Tokens stay env-only — nothing
# here is ever written to disk.
#
# POSIX sh, safe under `set -e` (no failing compound commands).

# Both CLIs want a full https URL; accept a bare hostname too.
_atlassian_host="${ATLASSIAN_URL:-${ATLASSIAN_HOST:-}}"
case "$_atlassian_host" in
    http://*|https://*|'') ;;
    *) _atlassian_host="https://$_atlassian_host" ;;
esac
CFL_URL="${CFL_URL:-$_atlassian_host}"
JIRA_SERVER="${JIRA_SERVER:-$_atlassian_host}"
CFL_EMAIL="${CFL_EMAIL:-${ATLASSIAN_EMAIL:-}}"
JIRA_LOGIN="${JIRA_LOGIN:-${ATLASSIAN_EMAIL:-}}"
CFL_API_TOKEN="${CFL_API_TOKEN:-${ATLASSIAN_API_TOKEN:-}}"
JIRA_API_TOKEN="${JIRA_API_TOKEN:-${ATLASSIAN_API_TOKEN:-}}"

export CFL_URL CFL_EMAIL CFL_API_TOKEN JIRA_API_TOKEN JIRA_SERVER JIRA_LOGIN