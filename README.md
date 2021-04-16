# Vala Language Server
[![Gitter](https://badges.gitter.im/vala-language-server/community.svg)](https://gitter.im/vala-language-server/community)

### Installation

We recommend using VSCode with the [Vala plugin](https://marketplace.visualstudio.com/items?itemName=prince781.vala).

- Guix: `guix install vala-language-server`

- Arch Linux (via AUR): `yay -S vala-language-server`
  or `yay -S vala-language-server-git`

- Alpine Linux Edge: `apk add vala-language-server`

- Ubuntu 20.04, 20.10, 21.04, Fedora 33, Debian, openSUSE, and Mageia

  **The Ubuntu PPA and Fedora Copr are now deprecated.** We have moved to an
  automated build and packaging system, Open Build System, at
  [here](https://software.opensuse.org//download.html?project=home%3APrince781&package=vala-language-server).
  You can find details about how to install VLS for your distribution
  at that link.

  For example, to install VLS on **Ubuntu 21.04**, first add the repository:

  ```
  echo 'deb http://download.opensuse.org/repositories/home:/Prince781/xUbuntu_21.04/ /' | sudo tee /etc/apt/sources.list.d/home:Prince781.list
  curl -fsSL https://download.opensuse.org/repositories/home:Prince781/xUbuntu_21.04/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_Prince781.gpg > /dev/null
  ```

  And then update and install VLS:

  ```
  sudo apt update
  sudo apt install vala-language-server
  ```

  For **Fedora 33**, add the repository like this:

  ```
  dnf config-manager --add-repo https://download.opensuse.org/repositories/home:Prince781/Fedora_33/home:Prince781.repo
  ```

  And then install:

  ```
  dnf install vala-language-server
  ```

  For Fedora and other RPM-based distributions (openSUSE, Mageia), you can also
  install `vala-languageserver-gb-plugin` for the **GNOME Builder plugin**.

  For **Debian**, add the repository like this:

  ```
  echo 'deb http://download.opensuse.org/repositories/home:/Prince781/Debian_Testing/ /' | sudo tee /etc/apt/sources.list.d/home:Prince781.list
  curl -fsSL https://download.opensuse.org/repositories/home:Prince781/Debian_Testing/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_Prince781.gpg > /dev/null
  ```

  And then install:

  ```
  sudo apt update
  sudo apt install vala-language-server
  ```

![VLS with VSCode](images/vls-vscode.png)
![VLS with Vim with coc.nvim and vista plugins](images/vls-vim.png)
![VLS with GNOME Builder](images/vls-gb.png)

## Table of Contents
- [Vala Language Server](#vala-language-server)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Dependencies](#dependencies)
  - [Setup](#setup)
    - [Installation](#installation)
    - [Building from Source](#building-from-source)
    - [With Vim](#with-vim)
    - [With Visual Studio Code](#with-visual-studio-code)
    - [With GNOME Builder](#with-gnome-builder)
  - [Contributing](#contributing)

## Features
- [x] diagnostics
- [x] code completion
    - [x] basic (member access and scope-visible completion)
    - [ ] advanced (context-sensitive suggestions)
- [x] document symbol outline
- [x] goto definition
- [x] symbol references
- [x] goto implementation
- [x] signature help
    - active parameter support requires upstream changes in vala and is disabled by default. use `meson -Dactive_parameter=true` to enable. see [this MR](https://gitlab.gnome.org/GNOME/vala/-/merge_requests/95). VLS by default uses a workaround that should satisfy 90% of cases.
- [x] hover
- [x] symbol documentation
    - [x] basic (from comments)
    - [x] advanced (from GIR and VAPI files)
        - this feature may be a bit unstable. If it breaks things, use `meson -Dparse_system_girs=false` to disable
- [x] search for symbols in workspace
- [x] highlight active symbol in document
- [x] rename symbols
- [ ] snippets
- [ ] code actions
- [ ] workspaces
- [ ] supported IDEs (see Setup below):
    - [x] vim with `vim-lsp` plugin installed
    - [x] Visual Studio Code
    - [x] GNOME Builder >= 3.36 with custom VLS plugin enabled (see below)
    - [ ] IntelliJ
- [ ] supported project build systems
    - [x] meson
    - [x] `compile_commands.json`
    - [ ] autotoools
    - [ ] cmake

## Dependencies
- `glib-2.0`
- `gobject-2.0`
- `gio-2.0` and either `gio-unix-2.0` or `gio-windows-2.0`
- `gee-0.8`
- `json-glib-1.0`
- `jsonrpc-glib-1.0`
- `libvala >= 0.48` latest bugfix release
- you also need the `posix` VAPI, which should come preinstalled

#### Install dependencies with Guix

To launch a shell with build dependencies satisfied:
```sh
guix environment vala-language-server
```

## Setup

### Building from Source
```sh
meson -Dprefix=$PREFIX build
ninja -C build
sudo ninja -C build install
```

This will install `vala-language-server` to `$PREFIX/bin`

### With Vim
Once you have VLS installed, you can use it with `vim` (or `nvim`).

#### coc.nvim
1. Make sure [coc.nvim](https://github.com/neoclide/coc.nvim) is installed.
2. After successful installation, in Vim run `:CocConfig` and add a new entry
   for VLS to the `languageserver` property like below:

```json
{
    "languageserver": {
        "vala": {
            "command": "vala-language-server",
            "filetypes": ["vala", "genie"]
        }
    }
}
```

#### vim-lsp
1. Make sure [vim-lsp](https://github.com/prabirshrestha/vim-lsp) is installed
2. Add the following to your `.vimrc`:

```vim
if executable('vala-language-server')
  au User lsp_setup call lsp#register_server({
        \ 'name': 'vala-language-server',
        \ 'cmd': {server_info->[&shell, &shellcmdflag, 'vala-language-server']},
        \ 'whitelist': ['vala', 'genie'],
        \ })
endif
```

### With Visual Studio Code
- Install the Vala plugin (https://marketplace.visualstudio.com/items?itemName=prince781.vala)

### With GNOME Builder
- Support is currently available with Builder 3.35 and up
- Running `ninja -C build install` should install the plugin to `$PREFIX/lib/gnome-builder/plugins`. Make sure you disable the GVLS plugin.

## Contributing
Want to help out? Here are some helpful resources:

- If you're a newcomer, check out https://github.com/benwaffle/vala-language-server/issues?q=is%3Aissue+is%3Aopen+label%3Anewcomers
- Gitter room is for project discussions: https://gitter.im/vala-language-server/community
- `#vala` on gimpnet/IRC is for general discussions about Vala and collaboration with upstream
- Vala wiki: https://wiki.gnome.org/Projects/Vala/
- libvala documentation:
    - https://benwaffle.github.io/vala-language-server/index.html
    - https://gnome.pages.gitlab.gnome.org/vala/docs/index.html
