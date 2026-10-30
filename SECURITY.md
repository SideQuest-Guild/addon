# Security

## Reporting a problem

Report security problems privately through
[GitHub's private reporting](https://github.com/SideQuest-Guild/addon/security/advisories/new), not in a
public issue. That covers the addon, the `sidequest-sync` uploader, and anything that could leak a sync token or let
someone change another player's points.

Only the latest release gets fixes.

## Checking a download

Every release zip is built by GitHub Actions from a signed tag. The same file goes to CurseForge and to
[GitHub releases](https://github.com/SideQuest-Guild/addon/releases), and GitHub releases can't be changed
once published. To check that a zip came from this repo's release workflow, install the [GitHub CLI](https://cli.github.com/)
and run:

```sh
gh attestation verify SideQuest-v0.2.0-forever.zip --repo SideQuest-Guild/addon
```

To check a zip against the GitHub release it came from:

```sh
gh release verify-asset v0.2.0 SideQuest-v0.2.0-forever.zip --repo SideQuest-Guild/addon
```

Each release also carries an SPDX SBOM (`.spdx.json`) listing every file in the zip with its SHA-256, and
`SHA256SUMS.txt`.
