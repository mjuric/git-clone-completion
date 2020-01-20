from conftest import *

#@pytest.mark.skip
class TestGitClone:
    def test_service_completions(self, bash):
        # test service completions with an empty projects directory

        # basic service completions
        for cmdline, expected_result in [
            ("git clone ",                              [ "git@gitlab.com:", "https://gitlab.com/", 
                                                          "git@bitbucket.org:", "https://bitbucket.org/",
                                                          "git@github.com:", "https://github.com/" ]),
            ("git clone gi",                            [ "git@gitlab.com:", "git@bitbucket.org:", "git@github.com:" ]),
            ("git clone git@git",                       [ "git@gitlab.com:", "git@github.com:" ]),
            ("git clone git@gith",                      [ "ub.com:" ]),
            ("git clone notexists",                     [ ]),
        ]:
            expected_result.sort()

            result = bash.complete(cmdline)
            assert result == expected_result, f"Unexpected completion for `{cmdline}`"

        # service URL completion attempts with an empty directory
        # -- should result in no completion
        for service in services:
            for cmdline, expected_result in [
                ("git clone git@{service}",                 [ ":" ]),
                ("git clone git@{service}:",                [ ]),
            ]:
                cmdline = cmdline.format(service=service)

                expected_result = [ r.format(service=service) for r in expected_result ]
                expected_result.sort()

                result = bash.complete(cmdline)
                assert result == expected_result, f"Unexpected completion for `{cmdline}`"

    def test_org_completions(self, bash, projects):
        # test org completions with non-empty $projects directory.
        # should result in directory completions from $projects
        for service in services:
            for cmdline, expected_result in [
                ("git clone git@{service}:",            [ 'foo/', 'bar/', 'baz/' ]),
                ("git clone git@{service}:b",           [ 'bar/', 'baz/' ]),
                ("git clone https://{service}/",        [ 'foo/', 'bar/', 'baz/' ]),
                ("git clone https://{service}/b",       [ '//{service}/bar/', '//{service}/baz/' ]),
            ]:
                cmdline = cmdline.format(service=service)

                expected_result = [ r.format(service=service) for r in expected_result ]
                expected_result.sort()

                result = bash.complete(cmdline)
                assert result == expected_result, f"Unexpected completion for `{cmdline}`"
