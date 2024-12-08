# dotfiles

My personal dotfiles repository, managed with [chezmoi](https://www.chezmoi.io/) and 1Password for sensitive information.

## Highlights

- **Cross-platform**: Configurations for Kali Linux in WSL and Windows 11.
- **Shells**: Zsh and PowerShell.
- **Terminal**: Windows Terminal.

## Installation

### Prerequisites

- **Kali Linux in WSL**:
    - [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
    - [age](https://github.com/FiloSottile/age)
    - [1Password CLI](https://developer.1password.com/docs/cli/get-started)

- **Windows 11**:
    - PowerShell 7
    - [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
    - [1Password CLI](https://developer.1password.com/docs/cli/get-started)

### Installation Steps

#### Zsh on Kali Linux in WSL

1. Install prerequisites:
    ```sh
    sudo apt install git age
    ```

2. Install chezmoi and apply the dotfiles:
    ```sh
    sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply rios0rios0
    ```

#### PowerShell 7 on Windows 11

1. Install PowerShell 7 from the Microsoft Store.

2. Install some dependencies using `winget` in PowerShell:
    ```powershell
    winget install --exact --id Git.Git --interactive
    winget install 1password-cli
    ```

3. Clone this repository and apply the dotfiles:
    ```powershell
    chezmoi init --apply rios0rios0
    ```

## Configuration

## Encryption

- Sensitive files are encrypted using [age](https://github.com/FiloSottile/age).
- Unix-specific decryption script: `run_before_decrypt-private-key-unix.sh.tmpl`
- Windows-specific decryption script: `run_before_decrypt-private-key-windows.ps1.tmpl`

## Additional Information

- Documentation for the setup can be found on my [notes website](https://rios0rios0.github.io/notes/setup/).

## References:

- https://github.com/patrick-5546/dotfiles
- https://github.com/budimanjojo/dotfiles
- https://www.chezmoi.io/user-guide/command-overview/
- https://www.chezmoi.io/reference/templates/variables/
- https://www.chezmoi.io/reference/special-files-and-directories/chezmoiscripts/
- https://masterminds.github.io/sprig/

## TODO:
- check how to avoid 1Password duplicated calls
- check how to use variables from an included template
