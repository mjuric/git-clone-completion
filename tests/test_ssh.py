from conftest import *

#@pytest.mark.skip
@pytest.mark.env(ignore_changes=r"^([+-]__ssh_.*=.*|\+RANDOM=.*)$")
class TestSSH:
    def test_basic(self, bash):
        for cmdline, expected_result in [
            ("git clone loc", []),					# initially has no autocompletions
            ("git clone localhost:f", ['localhost:foo/']),
            ("git clone localhost:foo/", ['localhost:foo/rep ']),
            ("git clone lo", ['localhost:'])				# should remembe the hostnme after a successful login
        ]:
            expected_result.sort()

            result = bash.complete(cmdline)
            assert result == expected_result, f"Unexpected completion for `{cmdline}`"

    def test_cache_expiration(self, bash):
        try:
            # test that we can expire the hostname after N tries
            N = 5
            for i in range(N):
                result = bash.complete(f"git clone test-dummy-{i}:foo/")
                assert result == f"test-dummy-{i}:foo/rep ", f"Unexpected completion for `{cmdline}`"
            assert bash.complete("git clone loc") == [], f"Didn't expire a host from cache"

            # test that successful login refreshes the item in the cache

            # after the above, localhost should still be out of the cache, and
            # test-dummy-0 should be next in line to be eliminated.
            # we'll rerun a completion to refresh its status.
            assert bash.complete("git clone test-dummy-0:f") == [ 'test-dummy-0:foo/' ], f"Unexpected completion for `{cmdline}`"

            # verify that re-adding localhost won't squeeze test-dummy-0 out of the cache
            # and that test-dummy-1 got squeezed out
            assert bash.complete("git clone localhost:f") == [ 'localhost:foo/' ], f"Unexpected completion for `{cmdline}`"
            assert bash.complete("git clone test-dummy-0") == [ 'test-dummy-0:' ], f"Unexpected completion for `{cmdline}`"
            assert bash.complete("git clone test-dummy-1") == [], f"Didn't expire a host from cache"
        except:
            with open(f'{bash.homedir}/.cache/git-clone-completion/ssh.recent') as fp:
                print(fp.read())
            raise
