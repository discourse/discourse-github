# Discourse Github Linkback

This plugin will create a link from a Github pull request or commit
back to a Discourse post where it is mentioned.


## Installation

Follow the [plugin installation guide](https://meta.discourse.org/t/install-a-plugin/19157?u=eviltrout).

## After Installation

You need to enable the plugin on Settings -> Plugins.

You can generate an [access token](https://github.com/settings/tokens) on Github.
Be sure to give it <em>only</em> the `public_repo` scope. Paste that token into the
`github linkback access token` setting.

Finally, add the projects you wish to post to in the `github linkback projects`a
site setting.
