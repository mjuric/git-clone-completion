import pytest
import pexpect, os.path

import contextlib
import difflib
import os
import io
import re
import shlex
import subprocess
import tempfile
import shutil

#####################################

# Globals
_PS1 = "## unit-test-shell ## "
_BASH_SENTINEL = "__n83GbnQXP96pH7so__"  # generated with `openssl rand -base64 12 | tr -d =`
_TESTDIR = os.path.dirname(__file__)
_FIXTURESDIR = os.path.join(_TESTDIR, 'fixtures')

services=[ 'github.com', 'gitlab.com', 'bitbucket.org' ]
wordbreak_variants=["\"'><=;|&(:", "@\"'><=;|&(:"]

bash_versions=['/bin/bash']
for _bv in ['/usr/local/bin/bash']:
    if os.path.exists(_bv):
        bash_versions += [ _bv ]

have_git_completion = [ None ]
for _gc in [
    '/usr/share/doc/git-1.8.3.1/contrib/completion/git-completion.bash',		# CentOS 7
    '/Library/Developer/CommandLineTools/usr/share/git-core/git-completion.bash'	# MacOS
]:
    if os.path.exists(_gc):
        have_git_completion += [ _gc ]
        break

scope='function'

@pytest.fixture(scope=scope, params=bash_versions)
def bashpath(request):
    return request.param

@pytest.fixture(scope=scope, params=wordbreak_variants)
def wordbreaks(request):
    return request.param

@pytest.fixture(scope=scope, params=have_git_completion)
def git_completion(request):
    return request.param

@pytest.fixture(scope=scope)
def homedir(request):
    return 'new'

@pytest.fixture(scope=scope)
def bash(request, bashpath, homedir, wordbreaks, git_completion):
    name = homedir
    with tempfile.TemporaryDirectory() as dir:
        homedir = shutil.copytree(f'fixtures/{name}', f'{dir}/{name}')

        yield from _bash_aux(request, bashpath, homedir, wordbreaks, git_completion)

@pytest.fixture
def projects(request, bash):
    # copy a mock projects dir into homedir
    src = os.path.join(_FIXTURESDIR, 'projects')
    dst = os.path.join(bash.homedir, 'projects')
    shutil.copytree(src, dst)

    yield dst

    # remove the copy
    assert dst.startswith('/var/folders') or dst.startswith('/tmp'), f"Skipping temp dir removal out of abundance of caution: {dst}"
    shutil.rmtree(dst)

#####################################

#####################################
#
# Helpers
#

def assert_bash_run(bash, cmd, expect_output=True, expect_newline=True):
    # Send command
    bash.sendline(cmd)
    bash.expect_exact(cmd)

    # Find prompt, output is before it
    bash.expect_exact("%s%s" % ("\r\n" if expect_newline else "", _PS1))
    output = bash.before

    # Retrieve exit status
    echo = "echo $?"
    bash.sendline(echo)
    got = bash.expect(
        [
            r"^%s\r\n(\d+)\r\n%s" % (re.escape(echo), re.escape(_PS1)),
            _PS1,
            pexpect.EOF,
            pexpect.TIMEOUT,
        ]
    )
    status = bash.match.group(1) if got == 0 else "unknown"

    assert status == "0", f'Error running "{cmd}": exit status={status}, output="{output}"'
    if output:
        assert expect_output, f'Unexpected output from "{cmd}": exit status={status}, output="{output}"'
    else:
        assert not expect_output, f'Expected output from "{cmd}": exit status={status}, output="{output}"'

    return output

@contextlib.contextmanager
def assert_unmodified_env(bash, ignore=""):

    before_env = get_env(bash)

    yield

    # reset the prompt
    bash.sendintr()
    bash.expect_exact(_PS1)

    # check env hasn't been modified
    after_env = get_env(bash)
    diff_env(before_env, after_env, ignore)

def get_env(bash):
    return (
        assert_bash_run(
            bash,
            "{ (set -o posix ; set); declare -F; shopt -p; set -o; }"
        )
        .strip()
        .splitlines()
    )

def diff_env(before, after, ignore):
    diff = [
        x
        for x in difflib.unified_diff(before, after, n=0, lineterm="")
        # Remove unified diff markers:
        if not re.search(r"^(---|\+\+\+|@@ )", x)
        # Ignore variables expected to change:
        and not re.search("^[-+](_|PPID|BASH_REMATCH|OLDPWD)=", x)
        # Ignore likely completion functions added by us:
        and not re.search(r"^\+declare -f _.+", x)
        # mjuric: weird solo empty lines on macOS, maybe other OS-es (??)
        and not x in '+-'
        # ...and additional specified things:
        and not re.search(ignore or "^$", x)
    ]
    # For some reason, COMP_WORDBREAKS gets added to the list after
    # saving. Remove its changes, and note that it may take two lines.
    for i in range(0, len(diff)):
        if re.match("^[-+]COMP_WORDBREAKS=", diff[i]):
            if i < len(diff) and not re.match(r"^\+[\w]+=", diff[i + 1]):
                del diff[i + 1]
            del diff[i]
            break
    assert not diff, "Environment should not be modified"

def _bash_aux(request, bashpath, homedir, wordbreaks, git_completion):
    #
    # environment modifications needed to facilitate testing
    #
    inputrc = f'{_FIXTURESDIR}/inputrc'
    bashrc = f'{_FIXTURESDIR}/bashrc'

    env = {}
    env.update(
        dict(
            PS1=_PS1,
            INPUTRC=inputrc,
            TERM="dumb",
            LC_COLLATE="C",
        )
    )

    #
    # requested environment modifications
    #
    env['COMP_WORDBREAKS'] = wordbreaks
    env['HOME'] = homedir

    #
    # environment changes to ignore
    #
    ignore_env = None
    marker = request.node.get_closest_marker("env")
    if marker:
        ignore_env = marker.kwargs.get("ignore_changes")

    # log output (we'll write this out to file if anything goes wrong)
    import io
    from random import randint
    log = io.StringIO()

    # Start and yield bash
    with pexpect.spawn(bashpath, timeout=10, cwd=homedir, env=env, logfile=log, encoding="utf-8", dimensions=(24, 160)) as bash:
        try:
            bash.expect_exact(_PS1)

            # add convenience methods and data
            bash.run = assert_bash_run.__get__(bash)
            bash.complete = assert_complete.__get__(bash)
            bash.bashpath = bashpath
            bash.homedir = homedir
            bash.wordbreaks = wordbreaks
            bash.git_completion = git_completion
            bash.PS1 = _PS1

            # git completions
            if git_completion:
                bash.run(f"source '{git_completion}'", expect_output=False)

            # install the library
            out = bash.run(f"source '{_TESTDIR}/../git-clone-completion.bash'", expect_output=not bash.git_completion)
            if out:
                assert out.startswith("\r\nwarning 1: *** no git autocompletion found"), "expected a warning message about no git autocompletion"

            # Load bashrc defs for testing and git-clone-completion
            bash.run(f"source '{bashrc}'")

            with assert_unmodified_env(bash, ignore=ignore_env):
                yield bash

        except:
            logfn = "_test-%d-.log" % randint(0, 10_000_000)

            with open(logfn, "w") as fp:
                fp.write(log.getvalue())

            raise

################################

class CompletionResult:
    """
    Class to hold completion results.
    """

    def __init__(self, output, items = None):
        """
        When items are specified, they are used as the base for comparisons
        provided by this class. When not, regular expressions are used instead.
        This is because it is not always possible to unambiguously split a
        completion output string into individual items, for example when the
        items contain whitespace.

        :param output: All completion output as-is.
        :param items: Completions as individual items. Should be specified
            only in cases where the completions are robustly known to be
            exactly the specified ones.
        """
        self.output = output
        self._items = None if items is None else sorted(items)

    def endswith(self, suffix):
        return self.output.endswith(suffix)

    def __eq__(self, expected):
        """
        Returns True if completion contains expected items, and no others.

        Defining __eq__ this way is quite ugly, but facilitates concise
        testing code.
        """
        expiter = [expected] if isinstance(expected, str) else expected
        if self._items is not None:
            return self._items == expiter
        return bool(
            re.match(
                r"^\s*" + r"\s+".join(re.escape(x) for x in expiter) + r"\s*$",
                self.output,
            )
        )

    def __contains__(self, item):
        if self._items is not None:
            return item in self._items
        return bool(
            re.search(r"(^|\s)%s(\s|$)" % re.escape(item), self.output)
        )

    def __iter__(self):
        """
        Note that iteration over items may not be accurate when items were not
        specified to the constructor, if individual items in the output contain
        whitespace. In those cases, it errs on the side of possibly returning
        more items than there actually are, and intends to never return fewer.
        """
        return iter(
            self._items
            if self._items is not None
            else re.split(r" {2,}|\r\n", self.output.strip())
        )

    def __len__(self):
        """
        Uses __iter__, see caveat in it. While possibly inaccurate, this is
        good enough for truthiness checks.
        """
        return len(list(iter(self)))

    def __repr__(self):
        return "<CompletionResult %s>" % list(self)

# Applies any \b chars the way they'd be seen on the terminal
# (deletes the previous character)
# FIXME: this can be implemented a lot more efficiently
def _remove_spinner_chars(text):
    out = io.StringIO()

    for c in text:
        if c != '\b':
            out.write(c)
        else:
            out.seek(out.tell()-1)

    return out.getvalue()

def assert_complete(bash, cmd, skipif=None, xfail=None, cwd=None, env=None, ignore_spinner=True):
    if skipif:
        try:
            assert_bash_exec(bash, skipif)
        except AssertionError:
            pass
        else:
            pytest.skip(skipif)

    if xfail:
        try:
            assert_bash_exec(bash, xfail)
        except AssertionError:
            pass
        else:
            pytest.xfail(xfail)

    if cwd:
        assert_bash_exec(bash, "cd '%s'" % cwd)

    env_prefix = "_BASHCOMP_TEST_"
    if env:
        # Back up envvars to be modified and set the new ones
        assert_bash_exec(
            bash,
            " ".join('%s%s="$%s"' % (env_prefix, k, k) for k in env.keys()),
        )
        assert_bash_exec(
            bash,
            "export %s" % " ".join("%s=%s" % (k, v) for k, v in env.items()),
        )

    # trigger tab-completion
    bash.send(cmd + "\t")
    bash.expect_exact(cmd)
    # FIXME: I worry there may be a race condition in here. Can bash receive
    # and echo back the sentinel _before_ the completion is echoed to the
    # screen?
    bash.send(_BASH_SENTINEL)
    got = bash.expect(
        [
            # 0: multiple lines, result in .before
            r"\r\n" + re.escape(_PS1 + cmd) + ".*" + _BASH_SENTINEL,
            # 1: no completion
            r"^" + _BASH_SENTINEL,
            # 2: on same line, result in .match
            r"^([^\r]+)%s$" % _BASH_SENTINEL,
            pexpect.EOF,
            pexpect.TIMEOUT,
        ]
    )

    if got == 0:
        output = _remove_spinner_chars(bash.before)
        if output.endswith(_BASH_SENTINEL):
            output = output[: -len(_BASH_SENTINEL)]
        result = CompletionResult(output)
    elif got == 1:
        result = CompletionResult("", [])
    elif got == 2:
        output = _remove_spinner_chars(bash.match.group(1))
        spc = output[len(output.rstrip()):]	# append any trailing space, as that's significane
                                                # (e.g., some completions must add a space, while others
                                                # must not)
        result = CompletionResult(output, [shlex.split(cmd + output)[-1] + spc])
    else:
        # This shouldn't happen unless there's an issue (or the race condition
        # mentioned above under FIXME)
        assert False, f"Match is different than expected (got={got})"

    # FIXME: sent CTRL-C to clear out the line. this sometimes doesn't work (bash
    # misses the CTRL-C) for reasons I've yet to undersdand. Maybe the completion
    # (or prompt-generation?) script is still running when it receives CTRL-C? In
    # any case, re-sending the CTRL-C seems to do the trick, so we keep doing it
    # until it works 
    for _ in range(5):
        bash.sendintr()
        try:
            bash.expect_exact(_PS1, timeout=0.1)
            break
        except pexpect.TIMEOUT:
            pass
#            print(f"LOGFILE={bash._logfn}")
#            print(f"cmd={cmd} result={result}")
#            print(bash.read_nonblocking(size=100000))
#            bash.sendintr()
#             bash.expect_exact(_PS1, timeout=0.1)
    else:
        assert False, f"Failed to clear the command line; something went wrong ☹️"

    if env:
        # Restore environment, and clean up backup
        # TODO: Test with declare -p if a var was set, backup only if yes, and
        #       similarly restore only backed up vars. Should remove some need
        #       for ignore_env.
        assert_bash_exec(
            bash,
            "export %s"
            % " ".join('%s="$%s%s"' % (k, env_prefix, k) for k in env.keys()),
        )
        assert_bash_exec(
            bash,
            "unset -v %s"
            % " ".join("%s%s" % (env_prefix, k) for k in env.keys()),
        )

    # go back to original directory
    if cwd:
        assert_bash_exec(bash, "cd - >/dev/null")

    return result

