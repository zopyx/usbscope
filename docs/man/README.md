# Manual page and shell completions

`usbscope.1` is the roff manual page for the CLI (all four views and the options
of both implementations, the Python tool and the Swift twin). The completions
cover the same interface:

```
docs/man/usbscope.1                 the manual page
scripts/completions/_usbscope       zsh completion
scripts/completions/usbscope.bash   bash completion
```

The manual page is kept in sync **by hand** with `usbscope --help`
(`src/usbscope/cli.py` / `Sources/usbscope/main.swift`); there is no generator, so
change both sides together. Preview it without installing anything:

```console
man ./docs/man/usbscope.1
```

## Install (no sudo, per user)

All three steps install into the user's home, so no root is needed and nothing
system-wide is touched.

```console
# manual page → ~/.local/share/man/man1
mkdir -p ~/.local/share/man/man1
cp docs/man/usbscope.1 ~/.local/share/man/man1/
man usbscope                 # add ~/.local/share/man to MANPATH if `man` misses it

# zsh completion → ~/.zsh/completions (see the header of _usbscope for ~/.zshrc)
mkdir -p ~/.zsh/completions
cp scripts/completions/_usbscope ~/.zsh/completions/

# bash completion → ~/.local/share/bash-completion/completions
mkdir -p ~/.local/share/bash-completion/completions
cp scripts/completions/usbscope.bash \
    ~/.local/share/bash-completion/completions/usbscope
```

On macOS the system `bash` is 3.2, which does not auto-load the completions
directory; `source scripts/completions/usbscope.bash` from `~/.bashrc` (or use a
Homebrew `bash` 4.4+) instead.

The convenience targets do exactly the copies above:

```console
make man             # ~/.local/share/man/man1/usbscope.1
make completions     # ~/.zsh/completions/_usbscope + bash completion dir
```

A system-wide install (`/usr/local/share/man/man1`) works the same way but needs
`sudo`; it is deliberately not automated here.
