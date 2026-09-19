#!/bin/bash

# Runs a command in a new session, so it has no controlling terminal. Tools
# that open /dev/tty for a password (softwareupdate's volume-owner prompt)
# then fail at once instead of waiting on the terminal until the timeout.
run_without_controlling_tty() {
    /usr/bin/perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!\n"; exec { $ARGV[0] } @ARGV or die "exec: $!\n"' -- "$@"
}
