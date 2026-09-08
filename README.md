# Stash

A local-only clipboard manager for macOS.

[Website](https://stash.vinyl-stack.com/) · [Install](https://stash.vinyl-stack.com/#install) · [Uninstall](https://stash.vinyl-stack.com/#uninstall)

## Build and run

Requires Apple Silicon, macOS 15+, and Swift 6.2+. Install Apple's Command Line Tools with `xcode-select --install` if needed.

```sh
git clone https://github.com/vincedprime/stash.git
cd stash
zsh scripts/build-app.sh
open "$HOME/Applications/Stash.app"
```

The build script installs to `~/Applications/Stash.app`.

## Launch at login

After installing, run from the repository:

```sh
zsh scripts/install-login-item.sh
```

## Run checks

```sh
zsh scripts/check-regressions.sh
```

Checks use temporary data and a private clipboard, leaving your history untouched.

[TODO](docs/todo.md)
