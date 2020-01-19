from conftest import *

#@pytest.mark.skip
@pytest.mark.skipif('GITHUB_TOKEN' not in os.environ, reason="GITHUB_TOKEN unset")
@pytest.mark.skipif('GITHUB_USERNAME' not in os.environ, reason="GITHUB_USERNAME unset")
class TestGitHub:
    def _auth(self, bash):
        token = os.environ['GITHUB_TOKEN']
        username = os.environ['GITHUB_USERNAME']

        bash.run(f"init-github-completion '{username}' '{token}'")

    def test_github_auth(self, bash):
        token = os.environ['GITHUB_TOKEN']
        username = os.environ['GITHUB_USERNAME']
        print(f"homedir: {bash.homedir}")
        print("HOME:" + bash.run("echo HOME=$HOME"))
        print("HOME:" + bash.run("echo GITHUB_TOKEN=$GITHUB_TOKEN"))

        # ensure we get the message about no being logged in
        result = bash.complete("git clone git@github.com:gh-test-acc/")
        assert result == ['completion currently disabled.', 'error: run `init-github-completion` to authenticate for repository completion.']

        # ensure we can log in
        bash.sendline('init-github-completion')
        bash.waitnoecho()
        bash.sendline(token)
        bash.expect('Your GitHub username: ')
        bash.sendline(username)

        auth_loc = f"{bash.homedir}/.config/git-clone-completion/github.auth.netrc"
        expect = f"Authentication setup complete; token stored to '{auth_loc}'"
        bash.expect_exact(expect)
        bash.expect_exact(bash.PS1)

    def test_github(self, bash):
        self._auth(bash)

        for cmdline, expected_result in [
            ("git clone git@github.com:gh-test-acc/", ['gh-test-acc/fomatic', 'gh-test-acc/foobar', 'gh-test-acc/foo', 'gh-test-acc/bar', 'gh-test-acc/private-repo']),
            ("git clone git@github.com:gh-test-acc/b", ['git@github.com:gh-test-acc/bar '])
        ]:
            expected_result.sort()

            result = bash.complete(cmdline)
            assert result == expected_result, f"Unexpected completion for `{cmdline}`"
