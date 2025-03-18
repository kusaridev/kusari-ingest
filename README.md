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

## Outputs

### `console_out`

Raw output of the kusari-uploader command

# License

The scripts and documentation in this project are released under the [Apache License](LICENSE)