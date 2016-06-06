# Discourse Github

This plugin will create a link from a Github pull request or commit
back to a Discourse post where it is mentioned.

## Installation

Follow the [plugin installation guide](https://meta.discourse.org/t/install-a-plugin/19157?u=eviltrout).

## After Installation

1.  You need to enable the plugin on Settings -> Plugins.

2.  Generate an [access token](https://github.com/settings/tokens) on Github.
    Be sure to give it <em>only</em> the `public_repo` scope. Paste that token into the
    `github linkback access token` setting.

3.  Finally, add the projects you wish to post to in the `github linkback projects` site setting in the formats:
    - `username/repository` for specific repositories
    - `username/*` for all repositories of a certain user

## github_badges

Assign badges to your users based on GitHub contributions!

##License

MIT
