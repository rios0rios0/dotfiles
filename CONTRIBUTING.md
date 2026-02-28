# Contributing

Contributions are welcome. By participating, you agree to maintain a respectful and constructive environment.

For coding standards, testing patterns, architecture guidelines, commit conventions, and all
development practices, refer to the **[Development Guide](https://github.com/rios0rios0/guide/wiki)**.

## Prerequisites

- [chezmoi](https://www.chezmoi.io/install/) 2.0+
- [Git](https://git-scm.com/downloads) 2.30+
- [age](https://github.com/FiloSottile/age) (for encrypted file handling)
- [1Password CLI](https://developer.1password.com/docs/cli/get-started) (for secrets management)

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
6. Verify the installation health:
   ```bash
   chezmoi doctor
   ```
7. If editing encrypted files, re-encrypt with age:
   ```bash
   chezmoi encrypt <file>
   ```
8. Commit following the [commit conventions](https://github.com/rios0rios0/guide/wiki/Life-Cycle/Git-Flow)
9. Open a pull request against `main`
