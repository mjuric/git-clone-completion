# Test suite

Note: this is currently in early stages of development and not expected to
be runnable by anyone other than mjuric.

## Setting up

```
conda install pytest pytest-xdist pexpect
```

SSH test setups:
```bash
# run this
./fixtures/remote-ssh-home/init-git.sh

# create identities
ssh-keygen -C git-clone-completion -N '' -f ~/.ssh/git-clone-completion

# add this to ~/.ssh/config (create the ~/.ssh/git-clone-completion identity first)
Host test-dummy-*
    HostName localhost
    User mjuric
    IdentitiesOnly yes
    IdentityFile ~/.ssh/git-clone-completion

# add this to ~/.ssh/authorized_keys
# echo "command=\"~/projects/github.com/mjuric/git-clone-completion/tests/ssh-preflight.sh\" $(cat ~/.ssh/git-clone-completion.pub)" >> ~/.ssh/authorized_keys
command="~/projects/github.com/mjuric/git-clone-completion/tests/ssh-preflight.sh" ...contents of ~/.ssh/git-clone-completion.pub...
```

## Running

```
. accounts.txt
pytest -rs -n=16
```
