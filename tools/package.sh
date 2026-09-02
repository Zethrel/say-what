#!/bin/sh
# Build the addon zip locally, the same shape the release workflow produces.
#
# Unzips into Interface\AddOns as SayWhat/, which is the folder name WoW
# requires. Run from the repository root:  sh tools/package.sh

set -eu

version=$(sed -n 's/^## Version: *//p' SayWhat/SayWhat.toc)
output="$PWD/SayWhat-v${version}.zip"

# Assembled in a staging directory rather than zipping SayWhat/ in place, so
# the license can travel with the addon without a second copy of it living in
# the repository. One LICENSE at the root stays the only one to keep current.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT INT TERM

cp -R SayWhat "$staging/SayWhat"
cp LICENSE "$staging/SayWhat/LICENSE"

rm -f "$output"
( cd "$staging" && zip -rq "$output" SayWhat )

# The whole point of this script: fail loudly if what we built is not what a
# player can actually install.
for required in 'SayWhat/SayWhat.toc' 'SayWhat/LICENSE'; do
	unzip -l "$output" | grep -q "$required" || {
		echo "the zip does not contain $required" >&2
		exit 1
	}
done

basename "$output"
