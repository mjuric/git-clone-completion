#!/bin/bash
#
# Create a few git repositories withing this fixture. This must be
# run before the tests are run.
#
# We create the repos this way (rather than pre-creating and committing
# them with the rest of the fixture) as git is unable to store a
# directory named .git
#


# go to the directory we're in
cd "$( dirname "${BASH_SOURCE[0]}" )"

for dir in "foo/rep" "weird/x = y/repo"; do
	if [[ -e "$dir/.git" ]]; then
		echo "'$dir/.git' already exists; skipping."
	else
		( cd "$dir" && git init )
	fi
done
