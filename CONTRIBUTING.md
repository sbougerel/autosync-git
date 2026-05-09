# Contributing to autosync-git

Thanks for your interest in contributing.

## Building

Byte-compile the package:

    make

This bootstraps a local package cache under `package-cache/` on first run.

## Running tests

    make test

Tests run against the `EMACS` binary in your `PATH`. Override with `make test EMACS=/path/to/emacs`. CI runs the suite against the Emacs versions listed in `.github/workflows/makefile.yml`.

## Cleaning

    make clean    # remove byte-compiled output
    make purge    # also remove package-cache/

## Submitting changes

- Keep the diff focused; one logical change per pull request.
- Add or update tests in `autosync-git-tests.el` for any behaviour change.
- The package must remain `package-lint` clean (CI enforces this via `elisp-check`).
- `README.md` is generated from the `;;; Commentary:` block of `autosync-git.el` via `make README.md`. Edit the commentary, not the README.

## License

Contributions are accepted under the same GPL-3.0-or-later license as the rest of the project.
