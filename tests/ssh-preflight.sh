#!/bin/bash
#
# A script intented to be used from command= stanza in ~/.ssh/authorized_keys
# which mocks a different HOME directory.
#

cd ~/projects/github.com/mjuric/git-clone-completion/tests/fixtures/remote-ssh-home

export HOME="$PWD"
exec bash --login
