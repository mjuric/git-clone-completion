# git-get: git clone with autocompletion for github

Clone a remote git repository to a predefined local location (`~/projects`,
by default), with bash autocompletion for github.com (it will auto-complete
a URL to repositories present in the typed organization).

![git-get gif](http://research.majuric.org/media/git-get.gif)

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

$ git get https://gitlab.com/gitlab-org/gitlab.git
Cloning into '/Users/mjuric/projects/gitlab.com/gitlab-org/gitlab'...
remote: Enumerating objects: 1807837, done.
remote: Counting objects: 100% (1807837/1807837), done.
remote: Compressing objects: 100% (366726/366726), done.
remote: Total 1807837 (delta 1415565), reused 1807152 (delta 1414948)
Receiving objects: 100% (1807837/1807837), 693.25 MiB | 8.16 MiB/s, done.
Resolving deltas: 100% (1415565/1415565), done.
Checking out files: 100% (27463/27463), done.
cloned to /Users/mjuric/projects/gitlab.com/gitlab-org/gitlab
```

## Installing

```
git clone https://github.com/mjuric/git-get
cd git-get

echo "## git-get setup"               >> ~/.bash_profile
echo "export PATH=\"$PWD:\$PATH\""    >> ~/.bash_profile
echo "source git-get-completion.bash" >> ~/.bash_profile

source git-get-completion.bash
git-get-login
```
