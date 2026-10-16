# WSL Preference

My projects live inside WSL (Kali Linux), NOT on the Windows filesystem.

When my working directory is a WSL path (e.g., `//wsl.localhost/kali-linux/...` or `//wsl$/kali-linux/...`), or when I mention a project that doesn't exist under `C:\Users\`:

- **Always** use `wsl -d kali-linux -- bash -c "<command>"` to run commands.
- **Never** try to access WSL projects via Windows paths like `/c/Users/rios0rios0/...` — they don't exist there.
- Use `wsl -d kali-linux -- bash -c "cat <file>"` or equivalent for reading files inside WSL.
- My WSL home directory is `/home/rios0rios0/` inside Kali Linux.
- When I ask to work on a project, assume it's in WSL unless explicitly stated otherwise.
