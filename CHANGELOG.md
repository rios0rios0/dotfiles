# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

When a new release is proposed:

1. Create a new branch `bump/x.x.x` (this isn't a long-lived branch!!!);
2. The Unreleased section on `CHANGELOG.md` gets a version number and date;
3. Open a Pull Request with the bump version changes targeting the `main` branch;
4. When the Pull Request is merged a new `git` tag must be created using [GitHub environment](https://github.com/rios0rios0/dotfiles/tags).

Releases to productive environments should run from a tagged version.
Exceptions are acceptable depending on the circumstances (critical bug fixes that can be cherry-picked, etc.).

## [Unreleased]

### Added

- added feature to use 1Password and SSH keys to encrypt and decrypt files
- added Windows feature to copy configuration inside `AppData` folder
- added feature to handle SSH, PEM and GPG keys seamlessly with 1Password
- added Linux WSL features to handle Git and SSH configuration with 1Password 
- added Shell Script features to handle watching multiple files (and compressing them) for Kubernetes secrets
- added a new feature to compress and watch many folders instead of just one folder
