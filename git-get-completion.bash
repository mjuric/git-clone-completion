#!/bin/bash
#
# git-get autocompletion script
#
# This script can be used as standalone, or can complement the one that ships with git.
#

# configuration
GG_CFGDIR=${XDG_CONFIG_HOME:-$HOME/.config/git-get}
GG_AUTHFILE="$GG_CFGDIR/github.auth.netrc"

init-github-completion()
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

# arg(s):
#    URL base (e.g., https://github.com/ or git@github.com:)
#    The (partial) 'org/repo' github URL fragment
# returns:
#    if -z $ERR, org/repo fragment completions in COMPREPLY
#    if -n $ERR, a message on what went wrong in COMPREPLY
_complete_github_fragment()
{
	local urlbase="$1"
	local URL="$2"

	# if more than one '/' character. this is not a valid github URL; stop.
	[[ $URL == */*/* ]] && return -1

	# are we're completing the org or the repo part?
	if [[ $URL != */* ]]; then
		#
		# completing the org: show a list of already cloned orgs
		#
		local PROJECTS="${PROJECTS:-$HOME/projects}"
		PROJECTS="$PROJECTS/github.com"

		WORDS=( $(ls "$PROJECTS" 2>/dev/null) )
		WORDS=( "${WORDS[@]/%//}" )
	else
		#
		# completing the repo: offer a list of repos available on github
		#
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
			COMPREPLY=("Error: run \`init-github-completion\` to activate repository completion." "completion currently disabled.")
			return
		fi
	fi

	# only return completions matching the typed prefix
	for i in "${!WORDS[@]}"; do
		if [[ ${WORDS[i]} == "$URL"* ]]; then
			COMPREPLY+=("${WORDS[i]}")
		fi
	done

	# user-friendly completions and colon handling
	compreply=( ${COMPREPLY[@]} )			# this is to be shown to the user
	COMPREPLY=("${COMPREPLY[@]/#/$urlbase}")
	__ltrim_colon_completions "$cur"		# these are the actual completions
	_fancy_autocomplete
}

# test if we're completing a fully qualified GitHub URL, complete it
# if so, return -1 otherwise.
#
# args:  $cur
#        <...> additional prefixes to compare to; pass "" to compare just the fragment
#
_complete_github_url()
{
	local cur="$1"
	shift

	local urlbase=
	for urlbase in "https://github.com/" "http://github.com/" "git@github.com:" "$@"; do
		[[ $cur != "$urlbase"* ]] && continue

		_complete_github_fragment "$urlbase" "${cur#"$urlbase"}"
		return
	done

	return -1
}

###############################################################
#
# Utilities
#

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
	# returned list of positional arguments
	posargs=( ${COMP_WORDS[0]} )

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
		posargs+=($c)
	done

	# set $argidx only if the current word was an argument
	[[ $o == 0 ]] && argidx=$idx || argidx=
}

# find and echo the common prefix of passed arguments
# inspired by https://stackoverflow.com/a/28647824
_common_prefix()
{
	[[ $# -eq 0 ]] && return 0

	local first prefix v
	first="$1"
	shift
	for ((i = 0; i < ${#first}; ++i)); do
		prefix=${first:0:i+1}
		for v; do
			if [[ ${v:0:i+1} != "$prefix" ]]; then
				echo "${first:0:i}"
				return
			fi
		done
	done

	echo "$first"
}

# adapted from https://github.com/torvalds/linux/blob/master/tools/perf/perf-completion.sh#L97
__ltrim_colon_completions()
{
    if [[ "$1" == *:* && "$COMP_WORDBREAKS" == *:* ]]; then
        # Remove colon-word prefix from COMPREPLY items
        local colon_word=${1%"${1##*:}"}  # "
        local i=${#COMPREPLY[*]}
        while [[ $((--i)) -ge 0 ]]; do
            COMPREPLY[$i]=${COMPREPLY[$i]#"$colon_word"}
        done
    fi
}

# complete words with colons
_fancy_autocomplete()
{
	# assumes the human-readable suggestions are in $compreply[]
	# assumes the completions are in $COMPREPLY[]
	# assumes the currently typed word is in $cur (with colons and all)

	# a single or no completions: bash will autocomplete
	[[ ${#COMPREPLY[@]} -le 1 ]] && return

	# check if the completions share a common prefix, and if
	# that prefix is longer than what's been typed so far. if so,
	# bash will autocomplete up to that prefix and not show the
	# suggestions (so send it the autocompletion text).
	local prefix=$(_common_prefix "${COMPREPLY[@]}")
	[[ "$prefix" != "${cur#*:}" ]] && return

	# Not possible to autocomplete beyond what's currently been
	# typed, so bash will show suggestions. Send the human-readable
	# form.
	#
	# Note: the appended character is the UTF-8 non-breaking space,
	# which sorts to the end.  It's needed to prevent bash from trying
	# to autocomplete a common prefix in the human-readable options, if
	# any.
	COMPREPLY=("${compreply[@]}" " ")
}

_colon_autocomplete()
{
	# save the human form
	compreply=("${COMPREPLY[@]}")
	__ltrim_colon_completions "$cur"
	_fancy_autocomplete
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

	_git()
	{
		local cur="${COMP_WORDS[COMP_CWORD]}"

		# check that the second positional arg is 'clone'
		__arg_index -C= -c= --exec-path= --git-dir= --work-tree= --namespace=

		[[ ${posargs[1]} == "clone" ]] && _git_clone && return
		[[ ${posargs[1]} == "get" ]] && _git_get && return
	}

	# Enable completion for git()
	complete -o bashdefault -o default -o nospace -F _git git 2>/dev/null || complete -o default -o nospace -F _git git
fi

# redefine _git_clone to auto-complete the first positional argument
_git_clone()
{
	# try standard completions, return if successful
	_git_clone_without_get
	[[ ${#COMPREPLY[@]} -gt 0 ]] && return

	# see if we're completing the second positional argument ('git clone <URL>')
	__arg_index $(__git clone --git-completion-helper)
	[[ $argidx -ne 2 ]] && return

	# Try to complete service URLs
	_complete_github_url "$cur" && return

	# Begin autocompleting towards a fully qualified http[s]://github.com/org/repo and git@github.com:org/repo forms
	COMPREPLY=($(compgen -W "https://github.com/ git@github.com:" "$cur"))
	_colon_autocomplete
}

# git's autocompletion scripts will automatically invoke _git_get() for 'get' subcommand
_git_get()
{
	# see if we're completing the apropriate positional argument
	__arg_index $(__git clone --git-completion-helper)

	local prog=$(basename ${COMP_WORDS[0]})
	local cur="${COMP_WORDS[COMP_CWORD]}"

	# 'git-get <URL>'
	[[ $prog == "git-get" && $argidx -eq 1 ]] && { _complete_github_url "$cur" ""; return; }

	# 'git get <URL>'
	[[ $prog != "git-get" && $argidx -eq 2 ]] && { _complete_github_url "$cur" ""; return; }
}

############
#
# Install completions
#

if [[ ! -f "$GG_AUTHFILE" ]]; then
	echo "warning: *** git-get completion disabled because you need to log in first ***"
	echo "warning: *** run 'init-github-completion' for a quick one-time setup.     ***"
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
			COMPREPLY_TRUE=( "mjuric/lsd" "mjuric/lsd-setup" " ")
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

