# kusari-ingest Action

This Action ingests various artifacts (such as SBOMs, SLSA and other attestations)  into the [Kusari Platform](https://www.kusari.dev/) as part of your github workflow. This will enable quick and easy integration to your tenant with very minimal input.

Authentication credentials (client-id, client-secret) are provided by the Kusari team. When using an [API key](https://docs.us.kusari.cloud/administration/api-keys), the key must be scoped with the `document_ingest` permission, plus `document_ingest_status_read` for `wait: true` (the default). Some optional inputs need more — see [available permissions](https://docs.us.kusari.cloud/administration/api-keys#available-permissions): `check-blocked-packages` and `results-file` also require `platform_data_read`, and `map-components` also requires `platform_data_read` and `platform_data_write`.

For details on how to query and utilize the data upon ingestion, please see our [documentataion](https://docs.us.kusari.cloud/).


## Usage

See [action.yaml](action.yaml)

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: [Your build and SBOM/Provenance generation steps]

  - uses: kusaridev/kusari-ingest@v0
    name: Kusari Ingestion
    with:
      file-path: './spdx.json'
      tenant-endpoint: 'https://[kusari-tenant-id].api.us.kusari.cloud'
      client-id: ${{ secrets.KUSARI_CLIENT_ID }}
      client-secret: ${{ secrets.KUSARI_CLIENT_SECRET }}
```

### Generating an SBOM from source

Set `generate: true` to have the action build a CycloneDX SBOM with `kusari platform generate` (mikebom) and upload it. No prebuilt SBOM file is required.

```yaml
  - uses: kusaridev/kusari-ingest@v0
    name: Kusari Ingestion (generate)
    with:
      generate: true
      source-path: '.'
      tenant-endpoint: 'https://[kusari-tenant-id].api.us.kusari.cloud'
      client-id: ${{ secrets.KUSARI_CLIENT_ID }}
      client-secret: ${{ secrets.KUSARI_CLIENT_SECRET }}
```

Or scan a container image instead of a source tree:

```yaml
  - uses: kusaridev/kusari-ingest@v0
    name: Kusari Ingestion (image)
    with:
      generate: true
      image: 'ghcr.io/myorg/myapp:${{ github.sha }}'
      tenant-endpoint: 'https://[kusari-tenant-id].api.us.kusari.cloud'
      client-id: ${{ secrets.KUSARI_CLIENT_ID }}
      client-secret: ${{ secrets.KUSARI_CLIENT_SECRET }}
```

mikebom auto-derives the SBOM's subject name/version when it finds a recognizable manifest (Cargo.toml, package.json, pom.xml, etc.), but falls back to generic names like `filesystem-scan` when scanning a container image or a directory without one. Set `root-name` / `root-version` to override the fallback:

```yaml
  - uses: kusaridev/kusari-ingest@v0
    name: Kusari Ingestion (image, with root identity)
    with:
      generate: true
      image: 'ghcr.io/myorg/myapp:${{ github.sha }}'
      root-name: ${{ github.event.repository.name }}
      root-version: ${{ github.ref_name }}@${{ github.sha }}
      tenant-endpoint: 'https://[kusari-tenant-id].api.us.kusari.cloud'
      client-id: ${{ secrets.KUSARI_CLIENT_ID }}
      client-secret: ${{ secrets.KUSARI_CLIENT_SECRET }}
```

### Ingestion results and auto-mapping components

Set the `results-file` input (or `map-components: true`) to capture machine-readable ingestion results — the software and component IDs for each ingested SBOM — exposed via the `results` output. When neither is set, the post-ingestion ID lookups are skipped entirely so plain uploads stay as fast as before. Set `map-components: true` to additionally ensure every ingested software is mapped to a Kusari component:

```yaml
  - uses: kusaridev/kusari-ingest@v0
    id: ingest
    name: Kusari Ingestion (with component mapping)
    with:
      file-path: './spdx.json'
      map-components: true
      tenant-endpoint: 'https://[kusari-tenant-id].api.us.kusari.cloud'
      client-id: ${{ secrets.KUSARI_CLIENT_ID }}
      client-secret: ${{ secrets.KUSARI_CLIENT_SECRET }}

  - name: Use the ingestion results
    env:
      RESULTS: ${{ steps.ingest.outputs.results }}
    run: jq '.sboms[].software_id' <<<"$RESULTS"
```

With `map-components: true`, the kusari CLI (`kusari platform upload --map-components`) ensures each ingested SBOM whose software is not already mapped to a component gets one: it creates a component named after the software (reusing an existing component with that name if one exists) and assigns the software to it. If the platform rejects the assignment because that component already has a source software, a fresh component named `<software-name>-<suffix>` is created instead, where the suffix is a short prefix of the ingested SBOM file's sha256. Each mapping is verified before the upload succeeds.

> **API key permissions:** `results-file` requires a key scoped with `platform_data_read` (for the post-ingestion ID lookups). `map-components` requires both `platform_data_read` and `platform_data_write` — creating a component and assigning software to it are writes, while verifying the mapping and looking up existing components by name are reads, so `platform_data_read` alone is not enough. See [available permissions](https://docs.us.kusari.cloud/administration/api-keys#available-permissions).

## Inputs

### `file-path`

**Required** when `generate` is `false` (default). Must be empty when `generate` is `true` — the action uploads the generated SBOM, not a pre-existing file. Path to directory or specific file to ingest.

### `generate`

**Optional** - When `true`, the action first runs `kusari platform generate` (via mikebom) on `source-path` to produce an SBOM, then uploads that SBOM. Default: `false`.

### `source-path`

**Optional** - Source path scanned by mikebom when `generate` is `true`. Passed as `--path`. Exactly one of `source-path` or `image` is required when `generate` is `true`. Default: `""`.

### `image`

**Optional** - Container image to scan when `generate` is `true`. Accepts an OCI reference (e.g. `ghcr.io/foo/bar:tag`) or the path to a `docker save` tarball. Passed to mikebom as `--image`. Exactly one of `source-path` or `image` is required when `generate` is `true`. Default: `""`.

### `output-path`

**Optional** - Where the generated SBOM is written and what is uploaded afterwards. Passed to mikebom as `--output`. Default: `project.cdx.json`. Set this (and a matching format flag in `mikebom-args`) to produce SPDX, e.g. `project.spdx.json`.

### `mikebom-args`

**Optional** - Extra arguments appended verbatim to `mikebom sbom scan` after `--`. Do not pass `--output`, `--root-name`, or `--root-version` here; use the `output-path`, `root-name`, and `root-version` inputs instead — the action will error on the conflict.

### `root-name`

**Optional** - Passed to mikebom as `--root-name` when set, so the generated SBOM's `metadata.component.name` reflects the value (rather than mikebom's generic fallback like `filesystem-scan`). When left empty, mikebom uses its own auto-derivation. To override only the value Kusari Platform reads at ingestion (without changing the SBOM file's contents), use `sbom-subject-name-override` instead. Default: `""`.

### `root-version`

**Optional** - Passed to mikebom as `--root-version` when set, so the generated SBOM's `metadata.component.version` reflects the value. When left empty, mikebom uses its own auto-derivation. To override only the value Kusari Platform reads at ingestion, use `sbom-subject-version-override` instead. Default: `""`.

### `tenant-endpoint`

**Required** - Kusari Platform tenant api endpoint

### `client-id`

**Required** - Client id for auth token provider

### `client-secret`

**Required** - Client secret for auth token provider

### `token-endpoint`

**Required** - Kusari Platform auth token provider endpoint

### `alias`

**Deprecated** - Not used by the Kusari platform; will be removed in a future release. Default: `""`

### `document-type`

**Optional** - Type of the file being uploaded. Default: `""`

### `open-vex`

**Optional** - Set to true if ingesting an OpenVEX document. When true, tag is required and so is one of software-id and sbom-subject. Default: `false`

### `tag`

**Optional** - Tag for the document. Currently only used for OpenVEX. Example: `govulncheck`

### `software-id`

**Optional** - Kusari Platform software ID that the document applies to. Currently only used for OpenVEX. Example: `1234`

### `sbom-subject`

**Optional** - Kusari Platform software SBOM subject substring value that uniquely indicates which software that the document applies to. Currently only used for OpenVex. Example: `kusari-ingest`

### `check-blocked-packages`

**Optional** - Check SBOM dependencies against the Blocked Package list in the Kusari Platform. If a blocked package is found the program will terminate with a non-zero exit status, failing the job. API keys additionally require the `platform_data_read` permission. Default: `false`

### `sbom-subject-name-override`

**Optional** - SBOM Subject Name override (for SBOMs only). Overrides the subject name the Kusari Platform reads from the uploaded SBOM document at ingestion time; the SBOM file's own `metadata.component.name` is unchanged. To change what mikebom writes *inside* the generated SBOM, use `root-name` instead (generate mode only). Default: `""`

### `sbom-subject-version-override`

**Optional** - SBOM Subject Version override (for SBOMs only). Overrides the subject version the Kusari Platform reads from the uploaded SBOM document at ingestion time; the SBOM file's own version field is unchanged. To change what mikebom writes *inside* the generated SBOM, use `root-version` instead (generate mode only). Default: `""`

### `commit-sha`

**Optional** - Commit SHA to associate with the uploaded document. Default: `${{ github.sha }}`

### `wait`

**Optional** - Wait for ingestion status. When set to `true`, the action will wait for the ingestion process to complete and report the final status. When set to `false`, the action will return immediately after uploading without waiting for processing to complete. Default: `true`

### `results-file`

**Optional** - Path to write the ingestion results JSON to. Setting this (or `map-components: true`) also populates the `results` output; when neither is set the ID lookups are skipped entirely. Requires `wait: true` (the default). API keys additionally require the `platform_data_read` permission. Default: `""`

### `map-components`

**Optional** - When `true`, passes `--map-components` to `kusari platform upload`: after ingestion, every ingested software gets mapped to a Kusari component — the CLI creates (or reuses) a component named after the software, assigns the software to it, then verifies the mapping. See [Ingestion results and auto-mapping components](#ingestion-results-and-auto-mapping-components). Requires `wait: true` (the default). API keys additionally require the `platform_data_read` and `platform_data_write` permissions. Default: `false`

## Automatic Repository Traceability

The action automatically captures repository metadata to enable traceability for dependency updates and code changes:

| Metadata | Source | Example |
|----------|--------|---------|
| `forge` | GitHub server URL | `github.com` or `github.enterprise.com` |
| `org` | Repository owner | `kusaridev` |
| `repo` | Repository name | `kusari-ingest` |
| `subrepo_path` | Derived from `file-path` in upload mode, from `source-path` in generate mode, and omitted in image mode | `app/frontend` (from `app/frontend/sbom.json`, or from `source-path: app/frontend`) |

This metadata is automatically attached to uploaded SBOMs without any additional configuration.

## Outputs

### `console_out`

Raw output of the kusari CLI upload command

### `results`

Contents of the ingestion results JSON: `{"sboms": [...]}` with the `sbom_id`, `sbom_subject`, `file_path`, `software_id`, `software_name`, `component_id`, and `component_name` for each ingested SBOM. Populated only when the `results-file` input is set or `map-components` is `true`; empty otherwise. When `map-components` is `true`, the results (and the `results-file` contents) are updated after mapping, so they reflect the final component assignments rather than the pre-mapping state. If the step fails partway (for example a mapping error after ingestion), `results` contains whatever the CLI wrote before failing — possibly pre-mapping or partially mapped state. Consumers that read `results` from a failed step (via `if: always()` or `continue-on-error`) should treat a `null` `component_id` as unmapped rather than assuming mapping completed.

## Testing

Run the test suite locally:

```sh
bash test/run-tests.sh
```

The tests cover `entrypoint.sh` input validation and flag plumbing (including `--results-file` and `--map-components` passthrough) using the mock kusari CLI in `test/mock/` — no network access, credentials, or real tenant required. The only dependencies are `bash` and `jq`. The component-mapping logic itself lives in the kusari CLI and is tested in the [kusari-cli](https://github.com/kusaridev/kusari-cli) repository.

# License

The scripts and documentation in this project are released under the [Apache License](LICENSE)