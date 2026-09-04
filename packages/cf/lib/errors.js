'use strict';

/** Raised for bad CLI input (bad URL, unknown flag, missing arg). */
class UsageError extends Error {}

/**
 * Print `cf: <msg>` to stderr and exit with the given code.
 * Codes: 1 usage, 2 auth, 3 API/network, 4 not found, 5 rate-limited.
 */
function fail(code, msg) {
  console.error('cf: ' + msg);
  process.exit(code);
}

module.exports = { UsageError, fail };