# kusari-ingest Action

This Action ingests various artifacts (such as SBOMs, SLSA and other attestations)  into the [Kusari Platform](https://www.kusari.dev/) as part of your github workflow. This will enable quick and easy integration to your tenant with very minimal input.

Authentication credentials (client-id, client-secret) are provided by the Kusari team.

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

## Inputs

### `file-path`

**Required** - Path to directory or specific file to ingest

### `tenant-endpoint`

**Required** - Kusari Platform tenant api endpoint

### `client-id`

**Required** - Client id for auth token provider

### `client-secret`

**Required** - Client secret for auth token provider

### `token-endpoint`

**Required** - Kusari Platform auth token provider endpoint

### `alias`

**Optional** - Alias of the package for grouping. Default: `""`

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

### `component-name`

**Optional** - Kusari Platform software component name (multiple SBOM subjects can belong to the same component). If a component with this name does not exist, it will be created. Default: `${{ github.event.repository.name }}`. Example: `kusari-ingest`

### `check-blocked-packages`

**Optional** - Check SBOM dependencies against the Blocked Package list in the Kusari Platform. If a blocked package is found the program will terminate with a non-zero exit status, failing the job. Default: `false`

### `sbom-subject-name-override`

**Optional** - SBOM Subject Name override (for SBOMs only). This allows you to override the subject name extracted from the SBOM document. Default: `""`

### `sbom-subject-version-override`

**Optional** - SBOM Subject Version override (for SBOMs only). This allows you to override the subject version extracted from the SBOM document. Default: `""`

### `wait`

**Optional** - Wait for ingestion status. When set to `true`, the action will wait for the ingestion process to complete and report the final status. When set to `false`, the action will return immediately after uploading without waiting for processing to complete. Default: `true`

## Outputs

### `console_out`

Raw output of the kusari CLI upload command

# License

The scripts and documentation in this project are released under the [Apache License](LICENSE)