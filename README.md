# Tktaalik

A Tk desktop application for [Fossil](https://fossil-scm.org) repositories,
tuned for the Tcl/Tk projects but usable with any Fossil repository.

The name comes from *Tiktaalik*, the fossil fish that came out of the water
on its fins: Fossil, brought out of the command line.

**It never pushes.**  Everything it changes stays in the local repository or
checkout, and is confirmed first.  Pushing stays your own step.

## What it does

Tktaalik shows a Fossil repository in one window: its history, tickets,
branches, tags, files, wiki, forum, the changes of the checkout, and a
search over all of them.  Most of what the `fossil` command does day to day
can be done from there.  It works on a checkout or on a repository file
alone.

## Requirements

- Tcl/Tk 8.6 or 9.0
- Fossil 2.x on the `PATH`, or the one the `FOSSIL` environment variable
  names (`FOSSIL=/opt/fossil/bin/fossil ./tktaalik`; see
  [Environment variables](docs/configuration.md#environment-variables));
  2.21 or newer (tested with 2.21, 2.23, 2.26, 2.28 and trunk)
- Optional: `patch`, to apply patches attached to tickets
- Optional: `curl`, to post to a forum through its web site

## Running

```sh
./tktaalik                 # the checkout in the current directory,
                           # else the repository used last
./tktaalik ~/src/tk        # a checkout
./tktaalik ~/src/tk.fossil # a repository file
```

## Installing

It runs from where it is unpacked.  To install it (the `tktaalik` command,
and the application menu with its icon):

```sh
./install.sh                    # in ~/.local (as root: /usr/local)
./install.sh --prefix /opt/tk   # elsewhere
./install.sh --wish wish9.0     # with another Tk shell
./install.sh --uninstall
```

`./install.sh --help` lists the options (`--destdir` for packages).

## The manual

The manual is in [`docs/`](docs/index.md).  In the application, **F1** opens
it at the part about what you are looking at.

## Development

Plain Tcl/Tk, no build step.  The tests run under Xvfb with Tk 8.6 and 9.0:

```sh
TKTAALIK_REPO=path/to/tk.fossil tests/run.sh   # the tests
tests/smoke.sh REPOSITORY...                   # on any repositories
```

`WISH` chooses the Tk shells they run with and `FOSSIL` the Fossil
([Environment variables](docs/configuration.md#environment-variables)).

[AGENTS.md](AGENTS.md) has the layout of the code and the rules for
changing it.

## License

BSD 2-Clause, see [LICENSE](LICENSE).
