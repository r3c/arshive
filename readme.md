# Arshive backup script

[![Build Status](https://img.shields.io/github/workflow/status/r3c/arshive/test/master)](https://github.com/r3c/arshive/actions/workflows/test.yml)
[![license](https://img.shields.io/github/license/r3c/arshive.svg)](https://opensource.org/licenses/MIT)

## Overview

Arshive is a simple backup tool written in pure shell script. It is designed to
perform periodic snapshots of any software data and rotate them to keep only
the last N archives. Being written as a shell script, Arshive can be added to
your crontab without any extra dependency.

## How to use

Checkout repository and place contents of the `src` directory anywhere in your
file system, e.g. `/opt/arshive/`.

Open and edit configuration file `arshive.conf` to declare one or more rule
file(s) (see `rules` option) defining backup rules. Other options can be
modified in this file to tweak the script behavior.

Open and edit rule file(s) (see sample `arshive.rule` file) to define how, when
and for how long backup files should be created. Each rule file can contain
one or more backup task declaration(s) to define how backup files should be
created and maintained.

Here is a sample rule declaring a backup task named "web-data" creating a
gzipped tar archive of everything within `/var/www` every two hour, and keeping
the three most recent backups created that way:

    web-data: cd /var/www && tar -czf {.tgz} *
      interval=7200
      keep=3

Run `archive.sh -q` every 5 minutes or so from your crontab. The "-q" flag will
suppress any non-error output so the tool will take care of executing any due
backup task and warn about anything that went bad.

## Rule options

Following rule options can be used to tweak a backup task:

- `interval=N`: create a backup only if latest one is more than N seconds old
  or if no backup was successfully created yet. Default value is 86400 (1 day).
- `keep=N`: keep the last N successfully created backup files and delete older
  ones. Default value is 7.
- `max_size=N`: log a warning if size of created backup file is larger than N
  bytes.
- `min_size=N`: log a warning if size of created backup file is smaller than N
  bytes.

## Resource

- Contact: v.github.com+arshive [at] mirari [dot] fr
- License: [license.md](license.md)
