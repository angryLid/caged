'use strict';

const { fail } = require('./errors');

/**
 * Credentials come straight from the environment — the same values caged
 * already passes for cfl / jira-cli (start-container.sh maps the shared
 * ATLASSIAN_* trio onto the CFL_* / JIRA_* vars):
 *
 *   email: CFL_EMAIL -> ATLASSIAN_EMAIL
 *   token: CFL_API_TOKEN -> ATLASSIAN_API_TOKEN -> JIRA_API_TOKEN
 *
 * No config file, no init, no keyring. The site is taken from the URL, so
 * CFL_URL is not needed here.
 *
 * Returns { email, token, authHeader } where authHeader is the HTTP Basic
 * value "Basic base64(email:token)". Exits with code 2 when anything is
 * missing.
 */
function getCredentials() {
  const email = process.env.CFL_EMAIL || process.env.ATLASSIAN_EMAIL || '';
  const token =
    process.env.CFL_API_TOKEN ||
    process.env.ATLASSIAN_API_TOKEN ||
    process.env.JIRA_API_TOKEN ||
    '';

  if (!email || !token) {
    const missing = [];
    if (!email) missing.push('email: set CFL_EMAIL or ATLASSIAN_EMAIL');
    if (!token) {
      missing.push('token: set one of CFL_API_TOKEN / ATLASSIAN_API_TOKEN / JIRA_API_TOKEN');
    }
    fail(
      2,
      'no credentials found in the environment.\n  missing ' + missing.join('\n  missing ') +
        '\n  (in caged these are normally already set by start-container.sh)'
    );
  }
  return {
    email,
    token,
    authHeader: 'Basic ' + Buffer.from(email + ':' + token, 'utf8').toString('base64'),
  };
}

module.exports = { getCredentials };