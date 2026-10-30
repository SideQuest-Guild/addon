# sidequest-sync

Watches World of Warcraft SavedVariables for the SideQuest addon and uploads
new `SQX1:` export strings to the SideQuest guild site's EPGP import API.

See the repository root `README.md` for full install and usage docs,
including the addon side of the sync workflow. Quick start:

```sh
uv run --directory uploader sidequest-sync login
uv run --directory uploader sidequest-sync once
uv run --directory uploader sidequest-sync watch
uv run --directory uploader sidequest-sync status
```
