# git-get: git clone with autocompletion for github

Clone a remote git repository to a predefined local location (`~/projects`,
by default), with bash autocompletion for github.com (it will auto-complete
a URL to repositories present in the typed organization).

## Usage

```
$ git get mjuric/ <TAB><TAB>
mjuric/conda                           mjuric/lsd                             mjuric/sims_maf_notebooks
mjuric/conda-build                     mjuric/lsd-setup                       mjuric/sssc-jupyterhub
mjuric/conda-lsst                      mjuric/lsst-pipe_tasks                 mjuric/staged-recipes

$ git get mjuric/conda-lsst
Cloning into '/Users/mjuric/projects/github.com/mjuric/conda-lsst'...
remote: Enumerating objects: 952, done.
remote: Total 952 (delta 0), reused 0 (delta 0), pack-reused 952
Receiving objects: 100% (952/952), 254.27 KiB | 5.08 MiB/s, done.
Resolving deltas: 100% (483/483), done.
cloned to /Users/mjuric/projects/github.com/mjuric/conda-lsst
```

## Installing

```
git clone https://github.com/mjuric/git-get
cd git-get

echo "## git-get setup"               >> ~/.bash_profile
echo "export PATH="$PWD:\$PATH"       >> ~/.bash_profile
echo "source git-get-completion.bash" >> ~/.bash_profile

source git-get-completion.bash
git-get-login
```
