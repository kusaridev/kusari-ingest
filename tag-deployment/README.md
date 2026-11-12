# kusari-ingest/tag-deployment Action

Tags a deployment in the [Kusari Platform](https://www.kusari.dev/). After a deploy, it tags the deployed image SBOM version with `environment=<value>`, finds the source SBOM version deployed with it (the source SBOM in the same component as the image SBOM), and tags that too. Earlier versions of both SBOMs lose the tag, so it always marks what is deployed now.

It installs the kusari CLI, logs in, and runs `kusari platform sboms tag-deployment`.

## Tagging a deployment

The build job uploads the image SBOM with the root `kusaridev/kusari-ingest` action and exposes its `sbom-id` and `sbom-version-id` outputs as job outputs. Those outputs are set only when `results-file` or `map-components` is set, and hold the first ingested SBOM's IDs. The deploy job passes them to this action after it deploys.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      sbom-id: ${{ steps.ingest.outputs.sbom-id }}
      sbom-version-id: ${{ steps.ingest.outputs.sbom-version-id }}
    steps:
      - uses: actions/checkout@v4

      - uses: [Your image build and push steps]

      - uses: kusaridev/kusari-ingest@v4
        id: ingest
        with:
          generate: true
          image: 'ghcr.io/myorg/myapp:${{ github.sha }}'
          results-file: kusari-results.json
          tenant-endpoint: 'https://[kusari-tenant-id].api.us.kusari.cloud'
          client-id: ${{ secrets.KUSARI_CLIENT_ID }}
          client-secret: ${{ secrets.KUSARI_CLIENT_SECRET }}

  deploy:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: read   # for the commit time lookup
    steps:
      - uses: [Your deploy steps]

      - uses: kusaridev/kusari-ingest/tag-deployment@v4
        with:
          sbom-id: ${{ needs.build.outputs.sbom-id }}
          sbom-version-id: ${{ needs.build.outputs.sbom-version-id }}
          value: prod
          tenant-endpoint: 'https://[kusari-tenant-id].api.us.kusari.cloud'
          client-id: ${{ secrets.KUSARI_CLIENT_ID }}
          client-secret: ${{ secrets.KUSARI_CLIENT_SECRET }}
```

This tags both versions `environment=prod`. To record another kind of deployment, set `label`: `label: region` with `value: eu-west` tags `region=eu-west` and leaves the `environment` tags as they are.

### Failures warn by default

Tagging runs after the deploy, so by default a failed tag does not fail the job. When tagging fails (bad credentials, the API is down, the CLI could not be installed, an empty `sbom-id` or `sbom-version-id`), the run shows a "Deployment tag failed" warning with the CLI's error, and the step passes. The annotation shows on every run until the cause is fixed. Set `fail-on-error: true` to fail the step instead.

If the source SBOM has no version to tag, the image version is still tagged, and the run shows a "Source SBOM not tagged" warning and adds the same line to the step summary. The step passes.

### Commit time

The CLI uses the deployed commit's committer date to pick the source SBOM version when none matches the image version's commit. When `commit-time` is empty, the action looks up the committer date of `github.sha` in `github.repository` through the GitHub API with `github-token`. The token needs `contents: read`. If the lookup fails, the run shows a "Commit time not found" warning and tags without a commit time; the lookup never fails the step.

Pass `commit-time` when the deploy runs in a different repo or at a different commit than the build. The lookup would find the deploy commit's time and could pick the wrong source SBOM version.

### API key permissions

When using an [API key](https://docs.us.kusari.cloud/administration/api-keys), it needs `platform_data_read` (to find the source SBOM version) and `platform_data_write` (to move the tags). See [available permissions](https://docs.us.kusari.cloud/administration/api-keys#available-permissions).

## Inputs

### `sbom-id`

**Required** - Kusari Platform SBOM ID of the deployed image SBOM: the root action's `sbom-id` output.

### `sbom-version-id`

**Required** - Kusari Platform version ID of the deployed image SBOM version: the root action's `sbom-version-id` output.

### `value`

**Required** - Where the version is deployed, such as `prod`. Tagged as `<label>=<value>`.

### `label`

**Optional** - Tag label. Default: `environment`

### `commit-time`

**Optional** - Committer date of the deployed commit, RFC3339 (e.g. `2026-10-01T12:00:00Z`). Passed as is when set. When empty, it is looked up for `github.sha`; see [Commit time](#commit-time). Default: `""`

### `github-token`

**Optional** - Token for the commit time lookup. Needs `contents: read`. Default: `${{ github.token }}`

### `tenant-endpoint`

**Required** - Kusari Platform tenant api endpoint

### `client-id`

**Required** - Client id for auth token provider

### `client-secret`

**Required** - Client secret for auth token provider

### `token-endpoint`

**Required** - Kusari Platform auth token provider endpoint. Default: `https://auth.us.kusari.cloud/oauth2/token`

### `fail-on-error`

**Optional** - When `true`, a failed tag fails the step. Otherwise it is a warning and the step passes. See [Failures warn by default](#failures-warn-by-default). Default: `false`

## Outputs

### `result`

The JSON the CLI printed: the `label`, the `value`, and for the `image` and `source` SBOMs the version tagged, whether the tag was `created`, `already_tagged` or `not_tagged`, and the versions the tag was ended on. When a step failed, the parts it did not finish are left out.
