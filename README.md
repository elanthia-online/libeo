# libeo

The shared library for the e-scripts on Lich 5. One loader,
`scripts/libeo.lic`, over a directory of small files, `scripts/eo/`, each
about one thing and readable on its own.

```
Script.loadlib('libeo')         how a script loads it, once per session
EO.require('0.2.0')             the version the script was built against
EO.use(command: ..., wait: ...)  the script's own helpers, lent to the library
```

## What is in it

| File | What it holds |
|---|---|
| `eo/version.rb` | `EO.require` and `EO.version`, the version gate |
| `eo/helpers.rb` | `EO.use`: a script lends its own helpers; `EO.command`, `EO.result`, `EO.settle`, `EO.go2` and `EO.say` call the running script's |

What lives here is script-side glue that Lich itself should not carry.
Anything that is a game rule or parser plumbing belongs in Lich and is called
directly; a script that needs it raises its required Lich version.

## Installing

libeo needs Lich 5.22.0 or later. It ships as a gem that carries the
library and an installer:

```
gem install libeo-<version>.gem
libeo install            # copies libeo.lic and eo/ into Lich's scripts/
libeo doctor             # what is installed and whether it is intact
libeo uninstall
```

Lich is found from `--lich-dir PATH`, else the `LICH_DIR` environment
variable, else the usual install places. From a checkout,
`ruby exe/libeo install --lich-dir PATH` does the same.

The installer records what it put there, so an upgrade removes files a newer
version dropped and an uninstall removes exactly what was installed.

## Developing

```
bundle install
bundle exec rspec        # the library's specs and the installer's
bundle exec rubocop
bundle exec rake gem     # builds dist/libeo-<version>.gem
```

The specs stand in for Lich's globals with small fakes; nothing needs a
running Lich. A tag `v<version>` builds the gem and attaches it to a GitHub
release.
