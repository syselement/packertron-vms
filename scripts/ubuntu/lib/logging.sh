#!/usr/bin/env bash

# Shared log-file filter for 02-provision-system.sh and 03-customize-system.sh.
#
# Both scripts send their output through `tee` so the console keeps live
# progress while the log file gets a readable transcript. This is the filter
# that produces the transcript.
#
# 00-update-system.sh and 01-cleanup-system.sh do not use it: Packer's shell
# provisioner uploads those two on their own, with no lib/ directory beside
# them, and neither writes its own log file.

# Strip ANSI escapes, then keep only the final state of a carriage-return
# redrawn line - dpkg and curl repaint progress with \r, so without this every
# intermediate percentage would be appended to the log.
#
# The `T keep` branch is what stops that second rule creating a new problem: a
# progress line ending in \r has nothing after the last one, so it collapses to
# an empty line rather than disappearing, and a single dpkg run leaves hundreds
# of them. `T` branches out for any line where no substitution happened - that
# is, any line with no \r at all - so only the collapsed remnants are deleted
# and the blank lines the scripts print between sections survive.
filter_log_output() {
    sed -u -r \
        -e 's/\x1B\[[0-9;]*[[:alpha:]]//g' \
        -e 's/.*\r//;T keep' \
        -e '/^$/d' \
        -e ':keep'
}
