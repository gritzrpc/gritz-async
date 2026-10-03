# Releasing

The first release is performed by the project owner. Build and review `pkg/gritz-async.gem` after all checks and CI pass, then stop before publishing or pushing the initial tag. Initial CHANGELOG notes remain exactly `Initial release.`.

For the first publication, the owner runs `gem push pkg/gritz-async.gem` from this repository, then configures the Trusted Publisher below. The first publication does not require pushing a tag. Later releases use the tag-triggered workflow.

Core 0.6.0 must be available on RubyGems before the release workflow runs. Configure this Trusted Publisher on RubyGems:

| Field | Value |
| --- | --- |
| Gem name | `gritz-async` |
| Repository owner | `gritzrpc` |
| Repository name | `gritz-async` |
| Workflow filename | `release.yml` |
| Environment | `release` |

Leave reusable-workflow repository fields empty. See the [RubyGems guide](https://guides.rubygems.org/trusted-publishing/).

For later releases, record user-visible changes, update the version, run tests, lint, dependency audit and strict build, commit and wait for main CI. Then push the matching `vVERSION` tag. The tag-triggered workflow validates the version and user impact, uses published dependencies, publishes through Trusted Publishing, and creates a GitHub release from CHANGELOG.

`rake release` only runs in the tag-triggered GitHub workflow. It creates no commits or tags. Before rerunning a failed release, verify whether RubyGems already accepted that version.
