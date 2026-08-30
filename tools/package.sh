#!/bin/sh
# Build the addon zip locally, the same shape the release workflow produces.
#
# Unzips into Interface\AddOns as SayWhat/, which is the folder name WoW
# requires. Run from the repository root:  sh tools/package.sh

set -eu

version=$(sed -n 's/^## Version: *//p' SayWhat/SayWhat.toc)
output="SayWhat-v${version}.zip"

rm -f "$output"
zip -rq "$output" SayWhat

# The whole point of this script: fail loudly if the folder name is wrong.
unzip -l "$output" | grep -q 'SayWhat/SayWhat.toc' || {
	echo "the zip does not contain SayWhat/SayWhat.toc" >&2
	exit 1
}

echo "$output"
