# git-clone-completions: GitHub autocompletion for `git clone` (and more)

A `bash` autocompletion script adding autocompletion of GitHub organizations
and repositories.

![autocompletion gif](http://research.majuric.org/media/git-clone-completions.gif)

## Usage

```
# place this into your ~/.bash_profile (Mac) or ~/.bashrc (Linux)
$ source git-clone-completions.bash

$ git clone <TAB><TAB>
git@github.com:      https://github.com/

$ git clone git@github.com:<TAB><TAB>
astronomy-commons/  dirac-institute/    lsst-dm/            lsst/               mjuric/

$ git clone git@github.com:astronomy-commons/<TAB><TAB>
astronomy-commons/aws-hub                        astronomy-commons/genesis-jupyterhub-automator
astronomy-commons/axs                            astronomy-commons/genesis-k8s-eks
astronomy-commons/axs-spark                      astronomy-commons/genesis-kafka-cluster
astronomy-commons/genesis-client                 astronomy-commons/helm-charts
astronomy-commons/genesis-helm-chart             astronomy-commons/tutorials
astronomy-commons/genesis-images

$ git clone git@github.com:astronomy-commons/genesis-jupyterhub-automator
Cloning into 'genesis-jupyterhub-automator'...
remote: Enumerating objects: 268, done.
remote: Counting objects: 100% (268/268), done.
remote: Compressing objects: 100% (161/161), done.
remote: Total 268 (delta 116), reused 228 (delta 80), pack-reused 0
Receiving objects: 100% (268/268), 3.21 MiB | 9.69 MiB/s, done.
Resolving deltas: 100% (116/116), done.
```
