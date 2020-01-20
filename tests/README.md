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

# add this to ~/.ssh/config (create the ~/.ssh/localhost identity first)
Host localhost
    HostName localhost
    User mjuric
    IdentityFile ~/.ssh/localhost

Host test-dummy-*
    HostName localhost
    User mjuric
    IdentityFile ~/.ssh/localhost

# add this to ~/.ssh/authorized_keys
```
command="~/projects/github.com/mjuric/git-clone-completion/tests/ssh-preflight.sh" ...public-key...
```

## Running

```
. accounts.txt
pytest -rs -n=16
```
