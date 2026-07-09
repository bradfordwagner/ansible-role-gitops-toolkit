# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this role does

Ansible role that installs and configures [gitops-toolkit](https://github.com/rumstead/gitops-toolkit) (a CLI that spins up local k3d clusters wired to ArgoCD) plus its dependent binaries: `kubectl`, `argocd` CLI, and `mkcert`. Optionally it also stands up the k3d clusters themselves and provisions mkcert-signed TLS secrets into them.

## Updating the gitops-toolkit version

Version is controlled by `gtk_ver` in `defaults/main.yml`. Check for the latest release at https://github.com/rumstead/gitops-toolkit/releases:

```yaml
gtk_ver: vX.Y.Z
```

## Updating dependent binaries/roles

Dependent binaries are installed via other Ansible roles pinned in `meta/requirements.yml`:

- `andrewrothstein.unarchivedeps`, `andrewrothstein.kubectl`, `andrewrothstein.argocd` — installed via `include_role` in `tasks/main.yml`
- `bradfordwagner.go-releaser-install` — installs `mkcert` (version pinned as `mkcert_version` in `vars/main.yml`), invoked with `vars.gri_installs` in `tasks/main.yml`

When bumping `bradfordwagner.go-releaser-install`, check its `tasks/install_binary.yml` for breaking changes to the `gri_installs` entry schema — e.g. the `is_binary: true` param was replaced by `unarchive_format: binary` between v1.2.0 and v1.5.0. Passing a stale param silently falls through to the default (`unarchive`) code path, which tries to resolve a `checksums.txt` that a raw-binary release (like mkcert) doesn't publish, and fails with a 404 mid-pipeline.

## CI/CD pipeline

Two GitHub Actions workflows build/test/publish the role via the [`bradfordwagner/dagger-container-builds`](https://github.com/bradfordwagner/dagger-container-builds) Dagger module (not Molecule):

- `.github/workflows/container_branches.yml` — runs on every push to any branch (tags excluded). Builds and runs `test.yml` across the OS/arch matrix defined in `config.yaml`. No publish step.
- `.github/workflows/container_tags.yml` — runs on tag push (`vX.Y.Z`-less plain semver tags, e.g. `1.9.3`). Same build/test matrix, plus a `publish` job that runs `robertdebock/galaxy-action` to publish to Ansible Galaxy.

`config.yaml` drives the build matrix (`flavor: ansible_role`) — OS list plus the upstream base image tag (`ghcr.io/bradfordwagner/ansible:X.Y.Z`). Bump `upstream.tag` here when the base ansible image is upgraded (see recent commit history for the `chore: upstream=X.Y.Z` pattern).

`workflow.yaml` and `dcb-os.yml` at the repo root are legacy Argo Workflows artifacts from before the Dagger-based pipeline (last touched 2023); they are not referenced by the current GitHub Actions workflows.

**Known Galaxy publish quirk:** `container_tags.yml`'s `galaxy-action` step derives the role name from the GitHub repo name rather than `meta/main.yml`'s `role_name: gitops_toolkit`, and passes `git_branch: ${{ github.ref_name }}` (the tag itself). As a result, published releases land on `bradfordwagner.gitops-toolkit` (hyphenated) on Galaxy, while `bradfordwagner.gitops_toolkit` (underscored, the name declared in `meta/main.yml`) is stuck on an old version. When installing this role via `ansible-galaxy`, use the hyphenated name to get current releases.

## Testing locally

`test.yml` is the role's test playbook (run inside the CI build containers, not meant to run standalone on a dev machine — it asserts installed binaries are runnable and diffs the rendered `~/.gitops-toolkit-clusters.yaml` against `tests/expected.clusters.yaml`). To exercise it end to end you need the full Dagger/container pipeline; there is no local `molecule test` equivalent.

## Architecture

`tasks/main.yml` is the orchestration entrypoint, executed roughly in this order:

1. Merge user-supplied `gtk_argocd` / `gtk_start_clusters` dicts over their `_defaults` counterparts (`vars/main.yml`) into internal `_gtk_argocd` / `_gtk_start_clusters` facts — this merge-over-defaults pattern is how nested dict variables get partial overrides.
2. `include_role` (each gated by `gtk_install_dependent_binaries`): `andrewrothstein.unarchivedeps` → `andrewrothstein.kubectl` → `andrewrothstein.argocd` → `bradfordwagner.go-releaser-install` (installs `mkcert`).
3. `tasks/install_gtk.yml` — downloads/checksums/installs the `gitops-toolkit` binary itself (separate from step 2's dependent-binaries roles, always runs).
4. `tasks/install_corp_cacert.yml` — optional corporate CA cert install, gated by `gtk_enable_corp_ca`.
5. Clone the ArgoCD deployment manifest git repo (`_gtk_argocd.manifest.git`).
6. Render `templates/clusters.yaml.j2` → `~/.gitops-toolkit-clusters.yaml`, the config file the `gitops-toolkit` binary consumes.
7. `tasks/start_clusters.yml` — gated by `_gtk_start_clusters.enabled`.

`tasks/start_clusters.yml` diffs the currently-running k3d clusters (`k3d cluster list`) against `gtk_clusters` (desired state) to decide what to tear down/rebuild, then shells out to `gitops-toolkit clusters` to actually build them, then issues kubeconfigs per cluster and points the default kube context at the first cluster with `git_ops` defined (the "admin" cluster). It contains WSL2-specific handling: native Docker on WSL2 doesn't resolve `host.docker.internal` for the ArgoCD agent container running on the k3d network, so it pre-creates the `localclusters` docker network and overrides `CRI_GATEWAY` with that network's gateway IP when `is_wsl` is true. `is_wsl` (in `vars/main.yml`) is detected via `/proc/version` containing "microsoft", with `WSL_DISTRO_NAME` as a fallback.

For each enabled cluster with `certs` defined, `tasks/start_clusters.yml` includes `tasks/clusters_loop.yml` (installs a local mkcert CA into `./.cache`) → `tasks/certs.yml` (generates a cert per `certs` entry and loads it into the cluster as a k8s Secret via `kubectl`).

`gtk_clusters` (in `defaults/main.yml`) is the central desired-state variable: a dict keyed by cluster name, each entry carrying `enabled`, `labels`, optional `annotations`, optional `git_ops` (marks the cluster as an ArgoCD "admin" cluster and configures the gitOps stanza in the rendered YAML), and optional `certs`. `templates/clusters.yaml.j2` renders this dict into the schema `gitops-toolkit` expects.
