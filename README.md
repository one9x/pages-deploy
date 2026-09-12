# Deploy to One9x Pages

Deploy a folder to [One9x Pages](https://one9x.com) and get the URL back.

```yaml
- uses: one9x/pages-deploy@v1
  with:
    site: mysite
    dir: dist
    token: ${{ secrets.ONE9X_TOKEN }}
```

## Setup, once

No One9x CLI yet? `curl -fsSL https://get.one9x.com | sh`, then `one9x login`.

**1. Create the site.** The action deploys to a site that already exists — it
will not create one for you.

```sh
one9x pages create mysite
```

**2. Mint a token** and store the printed secret as a repository secret named
`ONE9X_TOKEN` (Settings → Secrets and variables → Actions).

```sh
one9x tokens create "github actions"
```

The secret is shown once. **Tokens expire after 90 days** — `one9x tokens extend
<id>` pushes that out without changing the secret, so nothing has to be
re-stored. A silently expired token is the most likely way a working deploy
starts failing months later.

## Preview on every PR, publish on merge

One workflow covers both, because `deploy` is a string the caller computes:

```yaml
name: Pages
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: write      # only the PR comment needs this

concurrency:
  group: pages-${{ github.ref }}
  # A superseded preview is worth cancelling; a live deploy is not.
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  pages:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: npm run build

      - id: pages
        uses: one9x/pages-deploy@v1
        with:
          site: mysite
          dir: dist
          token: ${{ secrets.ONE9X_TOKEN }}
          deploy: ${{ github.ref == 'refs/heads/main' }}
          comment: true

      - if: steps.pages.outputs.live == 'true'
        run: echo "live at ${{ steps.pages.outputs.url }}"
```

A pull request **stages**: the release uploads but nothing goes live, and you get
a preview URL. A push to `main` **publishes**.

Staging costs nothing to keep. The blobs are already uploaded, so publishing
later is a pointer flip with nothing to rebuild — which also means the preview a
reviewer approved is byte-identical to what goes live.

## Inputs

| Input | Description | Default |
| --- | --- | --- |
| `site` | Site name (its subdomain) or numeric id. **Required.** | |
| `dir` | The folder to deploy — your build output. **Required.** | |
| `token` | A One9x machine token. **Required.** | |
| `deploy` | Publish immediately. Leave `false` to stage and get a preview URL. | `false` |
| `spa` | Serve `/index.html` for unknown paths (single-page apps). | `false` |
| `index` | Serve this file for `/` instead of `/index.html`. | |
| `error-pages` | One `<code>:<path>` per line, e.g. `404:/404.html`. | |
| `exclude` | One glob per line. Matches a single path segment — `**` is not supported. | |
| `tag` | Label this release. Tagged releases are pinned against retention. | |
| `cli-version` | Pin the One9x CLI. | the version this release was tested with |
| `portal` | Portal base URL. | `https://portal.one9x.com` |
| `comment` | Post a PR comment with the preview URL, updated in place on later pushes. | `false` |
| `comment-template` | Markdown for that comment. See below. | built-in |
| `github-token` | Token used to post the comment. | `${{ github.token }}` |

`spa` and `index` are the same setting — pass one, not both.

## Outputs

| Output | Description |
| --- | --- |
| `url` | The live URL. Empty unless this run published. |
| `preview-url` | The preview URL. Empty unless this run staged. |
| `version` | The release version — a content hash. |
| `seq` | The release number, as in `v6`. |
| `live` | `"true"` if this release is the one being served. |
| `unchanged` | `"true"` if the content matched an existing release and nothing new was created. |

`url` and `preview-url` are mutually exclusive: whichever does not apply is empty.

## The PR comment

`comment: true` posts one comment and **updates that same comment** on every
later push, so a long PR does not collect a wall of them. It needs
`permissions: pull-requests: write`; if that is missing the deploy still succeeds
and you get a warning rather than a failed build.

Override the body with `comment-template`. Placeholders are `{site}`, `{url}`,
`{preview_url}`, `{version}`, `{seq}` and `{commit}` — single braces, because
`${{ }}` already belongs to GitHub:

```yaml
    comment-template: |
      Preview for `{site}`: {preview_url}
```

## Common setups

**Single-page app** (React Router, Vue Router — any client-side routing):

```yaml
  with: { site: mysite, dir: dist, token: ..., spa: true }
```

Without `spa: true` a hard refresh on `/about` is a 404, because there is no
`about.html` to serve.

**A 404 page:**

```yaml
  with:
    error-pages: |
      404:/404.html
```

**Skip source maps:**

```yaml
  with:
    exclude: |
      *.map
```

**Approval before going live.** If merging to `main` is not the gate you want,
put the deploy in its own job with an `environment:` that has required
reviewers. (Don't try a conditional `environment:` on a single job — an empty
environment name is an error.)

## Notes

- **Linux and macOS runners.** The installer is a POSIX shell script; Windows
  runners are not supported.
- **Nothing changed?** Re-deploying identical content does not create a new
  release. The action succeeds, `unchanged` is `true`, and the outputs point at
  the release that already existed.
- Your build runs in your workflow; this action only uploads a folder. That is
  deliberate — no build settings to keep in sync with the ones you already have.

## Licence

MIT. See [LICENSE](LICENSE).
