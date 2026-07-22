# Contributing

Contributions are welcome. By participating, you agree to maintain a respectful and constructive environment.

For coding standards, testing patterns, architecture guidelines, commit conventions, and all
development practices, refer to the **[Development Guide](https://github.com/rios0rios0/guide/wiki)**.

## Prerequisites

- [chezmoi](https://www.chezmoi.io/install/) 2.0+
- [Git](https://git-scm.com/downloads) 2.30+
- [age](https://github.com/FiloSottile/age) (for encrypted file handling)
- [1Password CLI](https://developer.1password.com/docs/cli/get-started) (for secrets management)
- [Make](https://www.gnu.org/software/make/)

## Development Workflow

1. Fork and clone the repository
2. Create a branch: `git checkout -b feat/my-change`
3. Initialize chezmoi pointing to your local clone:
   ```bash
   chezmoi init --source ~/.local/share/chezmoi
   ```
4. Preview changes before applying:
   ```bash
   chezmoi diff
   ```
5. Apply dotfiles locally to test:
   ```bash
   chezmoi apply -v
   ```
6. Validate:
   ```bash
   make lint
   make test
   make sast
   ```
7. Verify the installation health:
   ```bash
   chezmoi doctor
   ```
8. If editing encrypted files, re-encrypt with age:
   ```bash
   chezmoi encrypt <file>
   ```
9. If your change **removes** a dependency, declare the removal (see below)
10. Update `CHANGELOG.md` under `[Unreleased]`
11. Commit following the [commit conventions](https://github.com/rios0rios0/guide/wiki/Life-Cycle/Git-Flow)
12. Open a pull request against `main`

## Removing a Dependency

This repository is a sync, not a bootstrapper. Deleting an `install_*()` function only
stops *new* machines from installing the tool — every machine that already ran the
installer keeps it. chezmoi has no concept of packages and no history of the source
state, so removals must be declared explicitly:

1. Delete the `install_*()` function (or package-list entry) from the platform's
   `run_once_before_*-install-dependencies.*` script.
2. Add a `"<strategy>:<target>"` tombstone to
   `.chezmoiscripts/run_onchange_after_<platform>-*-remove-dependencies.*` for **every**
   platform that installed it, commenting the removing commit.
3. Add any orphaned configuration directory to `.chezmoiremove`.

Available strategies: `apt`, `gh_extension`, `npm_global`, `path`, `pipx` (Linux/Android,
in `.chezmoitemplates/lib-remove-dependencies.sh`) and `npm_global`, `path`, `winget`
(Windows). Run `make test-remove-dependencies` after touching the removal library.

See [`.docs/dependency-lifecycle.md`](.docs/dependency-lifecycle.md) for the full
rationale and the alternatives that were evaluated.
