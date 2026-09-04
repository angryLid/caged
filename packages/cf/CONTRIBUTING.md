# Contributing to `@caged/cf`

This document covers package maintenance. Runtime usage is documented in [README.md](README.md).

## Tests

Run the offline test suite from the caged repository:

```sh
cd packages/cf && npm test
```

The tests do not require Confluence credentials.

## Packaging

Run `scripts/package-cf.sh` from the caged repository. The script creates:

```text
packages/cf/dist/caged-cf-<version>.tgz
```

`Containerfile.base` installs this artifact globally in the caged image. The installed package exposes this README at `$(npm root -g)/@caged/cf/README.md`.

## Runtime credential wiring

The caged `start-container.sh` script supplies the shared Atlassian environment variables. The package itself resolves credentials in `lib/auth.js`; it does not use a config file, initialization command, or keyring.
