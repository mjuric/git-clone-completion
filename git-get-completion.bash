#!/bin/bash
#
# git-get autocompletion script
#
# This script can be used as standalone, or can complement the one that ships with git.
#

# configuration
GG_CFGDIR=${XDG_CONFIG_HOME:-$HOME/.config/git-get}
GG_AUTHFILE="$GG_CFGDIR/github.auth.netrc"

git-get-login()
{
	# acquire credentials
	echo "Logging into github so we can list repositories..."
	echo "Please visit:"
	echo
	echo "    https://github.com/settings/tokens/new"
	echo
	echo "and generate a new personal access token:"
	echo
	echo "    1. Under 'Note', write 'git-get access for $USER@$(hostname)'"
	echo "    2. Under 'Select scopes', check 'repo:status' and leave otherwise unchecked."
	echo
	echo "Then click the 'Generate Token' green button (bottom of the page)."
	echo
	echo "The PAT is equivalent to a password git-get can use to securely access your github account."
	echo "Copy the newly generated token and paste it here."
	echo ""
	read -sp "Token (note: the typed characters won't show): " TOKEN; echo
	read -p "Your GitHub username: " GHUSER

	# securely store the token and user to a netrc-formatted file
	mkdir -p "$(dirname $GG_AUTHFILE)"
	rm -f "$GG_AUTHFILE"
	touch "$GG_AUTHFILE"
	chmod 600 "$GG_AUTHFILE"
	# note: echo is a builtin so this is secure (https://stackoverflow.com/a/15229498)
	echo "machine api.github.com login $GHUSER password $TOKEN" >> "$GG_AUTHFILE"

	# verify that the token works
	if ! curl -I -f -s --netrc-file "$GG_AUTHFILE" "https://api.github.com/user" >/dev/null; then
		curl -s "https://api.github.com/user"
		echo "Hmm, something went wrong -- most likely you've typed the token incorretly. Rerun and try again."
		exit -1
	else
		echo
		echo "Authentication setup complete; token stored to '$GG_AUTHFILE'"
	fi
}


# _refresh_repo_cache <org> <dest_cache_fn>
_refresh_repo_cache()
{
	local ORG="$1"
	local CACHE="$2"

	if [[ -n $(find "$CACHE" -newermt '-15 seconds' 2>/dev/null) ]]; then
		return
	fi
	mkdir -p $(dirname "$CACHE")
	touch "$CACHE"

	# extract the number of pages
	PAGES=$(curl -I -f -s --netrc-file "$GG_AUTHFILE" "https://api.github.com/users/$ORG/repos?page=1&per_page=1000" | 
		sed -En 's/^Link: (.*)/\1/p' |tr ',' '\n' | grep 'rel="last"' |
		sed -nE 's/^.*[?&]page=([0-9]+).*/\1/p')

	# fetch all pages to tmpfile and atomically replace the current cache (if any)
	local TMP="$CACHE.$$.$RANDOM.tmp"
	for page in $(seq 1 $PAGES); do
		curl -f -s --netrc-file "$GG_AUTHFILE" "https://api.github.com/users/$ORG/repos?page=$page&per_page=1000" >> "$TMP"
	done

	# extract repository names and store into the cache
	jq -r '.[].name' "$TMP" > "$CACHE"
	rm -f "$TMP"

	#echo "update to $CACHE done."
}

# get list of repositories from organization $1
# cache the list in .repos.cache.$1
_get_repo_list()
{
	local CACHEDIR=${XDG_CACHE_HOME:-$HOME/.cache/git-get}
	local CACHE="$CACHEDIR/repos.cache.$1"

	if [[ ! -f "$CACHE" ]]; then
		# this is the first time we're asking for the list of repos
		# in this organization; do it synchronously
		_refresh_repo_cache $1 $CACHE
	else
		# return what we have and fire off a background update
		( _refresh_repo_cache $1 $CACHE & )
	fi

	# return the list of repos
	REPOS=( $( cat "$CACHE" 2>/dev/null ) )
}

_complete_url()
{
	URL="$1"

	# URLs beginning with . are local -- let the normal bash autocompletion deal with them
	[[ $URL == .* ]] && return

	# Allow fully qualified http[s]://github.com/org/repo and git@github.com:org/repo forms
	if [[ $URL == "https://github.com/"* || $URL == "http://github.com/"* ]]; then
		URL=$(cut -d / -f 4- <<< "$URL")
	elif [[ $URL == "git@github.com:"* ]]; then
		IFS=':' read -ra A <<< "$URL"
		URL="${A[1]}"
	fi

	# if more than one '/' character. this is not a valid github URL; stop.
	[[ $URL == */*/* ]] && return

	# see if we're completing the org, or the repo part
	if [[ $URL != */* ]]; then
		# completing the org: show a list of already cloned orgs
		local PROJECTS="${PROJECTS:-$HOME/projects}"
		PROJECTS="$PROJECTS/github.com"

		WORDS=( $(ls "$PROJECTS") )
		WORDS=( "${WORDS[@]/%//}" )
	else
		# completing the repo: offer a list of repos available on github
		IFS='/' read -ra arr <<< "$URL"
		ORG=${arr[0]}
		REPO=${arr[1]}

		if [[ -f "$GG_AUTHFILE" ]]; then
			_get_repo_list "$ORG"
			WORDS=( "${REPOS[@]/#/$ORG/}" )		# prepend the org name
			WORDS=( "${WORDS[@]/%/ }" )		# append a space (so the suggestion completes the argument)
		else
			# short-circuit if we haven't authenticated, with
			# a helpful message
			COMPREPLY=("Error: run \`git-get-login\` to activate repository completion." "completion currently disabled.")
			return
		fi
	fi

	# only return completions matching the typed prefix
	for i in "${!WORDS[@]}"; do
		if [[ ${WORDS[i]} == "$URL"* ]]; then
			COMPREPLY+=("${WORDS[i]}")
		fi
	done
}

# If COMP_CWORD is a positional argument, set $argidx to its index
# ignoring any options that may have been specified before it.
#
# If COMP_CWORD is not a positional argument (e.g., it's an option
# or an option's argument), set $argidx to empty
#
# arguments: list of options that admit an argument, suffixed by '='
#
# example:
#     * assuming competion of `git clone --test foo`
#         __arg_index --foo= --bar= --baz=
#       sets argidx=2
#     * assuming competion of `git clone --test foo`
#         __arg_index --test=
#       sets argidx=
#     * assuming competion of `git clone --test foo -k`
#         __arg_index --test=
#       sets argidx=
#     * assuming competion of `git clone --test foo -k bar`
#         __arg_index --test=
#       sets argidx=2
#
__arg_index()
{
	local c p i idx=0
	for i in $(seq 1 $COMP_CWORD); do
		p=${COMP_WORDS[i-1]}	# previous word
		c=${COMP_WORDS[i]}	# current word
		o=1			# was this word an option (begin by assuming it was)?

		# an option
		[[ $c == -* ]] && continue

		# an argument of a previously specified option
		[[ $p == -* && p != -*=* ]] && (echo "$@" | grep -qw -- "$p=") && continue

		# a positional argument
		o=0
		idx=$((idx+1))
	done

	# set $argidx only if the current word was an argument
	[[ $o == 0 ]] && argidx=$idx || argidx=
}

############

# _git_clone enhancements

# Do we have git autocomplete?
if declare -F _git > /dev/null; then
	# Have we already (not) monkey-patched it?
	if  ! declare -F _git_clone_without_get > /dev/null; then
		# Duplicate and rename the '_git_clone' function
		eval "$(declare -f _git_clone | sed 's/_git_clone/_git_clone_without_get/')"
	fi
else
	# no git autocompletions; add shims and declare autocompletion
	__git() { git "$@"; }
	_git_clone_without_get() { : ; }
	
	TODO: declare autocompletion
fi

# redefine _git_clone to auto-complete the first positional argument
_git_clone()
{
	# try standard completions, return if successful
	_git_clone_without_get
	[[ ${#COMPREPLY[@]} -gt 0 ]] && return

	# stop if we're completing an option
	[[ $cur == -* ]] && return

	# stop if we're completing an option's argument (e.g., '--config cfgfile')
	local argopts=$(__git clone --git-completion-helper)
	echo "$argopts" | grep -qw -- "$prev=" && return

	# see if we're completing the second positional argument ('git clone <URL>')
	__arg_index "$argopts"
	[[ $argidx -ne 2 ]] && return

	# attempt URL completion
#	echo $'\n'"HERE! cur='$cur' COMP_CWORD=$COMP_CWORD argidx=$argidx"$'\n'
	_complete_url "$cur"
}

# git's autocompletion scripts will automatically invoke _git_get() for 'get' subcommand
_git_get()
{
	# see if we're completing the positional argument corresponding to the URL
	local prog=$(basename ${COMP_WORDS[0]})
	local cur="${COMP_WORDS[COMP_CWORD]}"

	__arg_index

	# 'git-get <URL>'
	[[ $prog == "git-get" && $argidx -eq 1 ]] && { _complete_url "$cur"; return; }

	# ('git get <URL>' or 'git-get <URL>')
	[[ $argidx -eq 2 ]] && { _complete_url "$cur"; return; }
}

############

#
# Install completions
#

if [[ ! -f "$GG_AUTHFILE" ]]; then
	echo "warning: *** git-get completion disabled because you need to log in first ***"
	echo "warning: *** run 'git-gen-login' for a quick one-time setip               ***"
fi

# If there's no git completion, at least install completion for our subcommand
if ! declare -F _git > /dev/null; then
	echo "warning: no git bash autocompletion found; installing standalone one for git-get" 1>&2
	complete -o bashdefault -o default -o nospace -F _git_get git 2>/dev/null \
		|| complete -o default -o nospace -F _git_get git
fi

# Enable completion for git-get even when not called as a git subcommand
complete -o bashdefault -o default -o nospace -F _git_get git-get 2>/dev/null \
	|| complete -o default -o nospace -F _git_get git-get


############

#
# Unit tests
#

_git_get_unit_test()
{
	for cmd in "git-get" "git get"; do
		for opts in "" "-s --long"; do
			# test succesful completions
			COMPREPLY_TRUE=( "mjuric/lsd " "mjuric/lsd-setup " )
			for url in "mjuric/lsd" "git@github.com:mjuric/lsd" "https://github.com/mjuric/lsd" "http://github.com/mjuric/lsd"; do
				COMPREPLY=()
				COMP_WORDS=($cmd $opts $url)
				COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1)) _git_get
				# compare the output vs expectation
				diff=$(diff <(printf "%s\n" "${COMPREPLY_TRUE[@]}") <(printf "%s\n" "${COMPREPLY[@]}"))
				[[ -n "$diff" ]] && { echo "[🛑] error: ${COMP_WORDS[@]} returned wrong completions" $'\n' "$diff"; return; }
				echo "[✔] ${COMP_WORDS[@]}"
			done

			# test completions that should fail
			for url in "./mjuric/lsd" "a/b/c" "git@github.com"; do
				COMPREPLY=()
				COMP_WORDS=($cmd $opts $url)
				COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1)) _git_get
				[[ ${#COMPREPLY[@]} == 0 ]] || { echo "[🛑] error: ${COMP_WORDS[@]} should've returned zero completions"; printf "%s\n" "${COMPREPLY[@]}"; return; }
				echo "[✔] ${COMP_WORDS[@]}"
			done
		done
	done
}

_arg_index_unit_test()
{
	COMP_WORDS=(git clone --test foo)
	COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1))
	__arg_index "--foo= --bar= --baz="; [[ $argidx == 2 ]] || { echo "test failed at line $LINENO"; return; }
	__arg_index --test=;                [[ -z $argidx ]]   || { echo "test failed at line $LINENO"; return; }

	COMP_WORDS=(git clone --test foo -k)
	COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1))
	__arg_index --foo= --bar= --baz=;   [[ -z $argidx ]]   || { echo "test failed at line $LINENO"; return; }

	COMP_WORDS=(git clone --test foo -k bar)
	COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1))
	__arg_index --test=;                [[ $argidx == 2 ]] || { echo "test failed at line $LINENO"; return; }
	
	echo "[✔] __arg_index unit tests succeeded."
}

