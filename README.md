# gitops_toolkit
=========

- Configures and installs https://github.com/rumstead/gitops-toolkit
- installs all required dependencies except for `docker` cli.

Published to Ansible Galaxy as `bradfordwagner.gitops-toolkit`.

## Requirements

- `docker` cli must already be installed on the target host (not managed by this role).
- min_ansible_version: 2.1

## Dependencies

Installed automatically via `meta/requirements.yml` when `gtk_install_dependent_binaries` is `true` (the default):

- `andrewrothstein.unarchivedeps`
- `andrewrothstein.kubectl`
- `andrewrothstein.argocd`
- `bradfordwagner.go-releaser-install` (installs `mkcert`)

## Role Variables

Key variables from `defaults/main.yml` (see the file for the full list and defaults):

| Variable | Default | Description |
|---|---|---|
| `gtk_ver` | `v1.2.3` | Version of `gitops-toolkit` to install |
| `gtk_parent_install_dir` | `/usr/local` | Parent install directory |
| `gtk_mirror` | `https://github.com/rumstead/gitops-toolkit/releases/download` | Download mirror |
| `gtk_install_dependent_binaries` | `true` | Whether to install `kubectl`, `argocd`, `mkcert`, etc. |
| `gtk_enable_corp_ca` | `false` | Whether to download/install a corporate CA cert (`gtk_corp_ca_url`, `gtk_corp_ca_path`) |
| `gtk_cluster_template_yaml` | `clusters.yaml.j2` | Template used to render `~/.gitops-toolkit-clusters.yaml` |
| `gtk_start_clusters.enabled` | `false` | Whether to actually build the k3d clusters (vs. just installing binaries/config) |
| `gtk_argocd` | see `defaults/main.yml` | ArgoCD namespace + manifest git repo settings for the admin cluster |
| `gtk_clusters_proxy` | `{all_proxy: "", no_proxy: ""}` | Proxy settings injected into each k3d cluster |
| `gtk_clusters` | see `defaults/main.yml` | Desired-state map of clusters to create — each entry has `enabled`, `labels`, optional `annotations`, optional `git_ops` (marks the cluster as the ArgoCD admin cluster), optional `certs` |

## Example Playbook

```yaml
- hosts: localhost
  roles:
    - role: bradfordwagner.gitops-toolkit
      gtk_argocd:
        namespace: argocd
        manifest:
          dir: "{{ ansible_env.HOME }}/deploy_argocd"
          git:
            enabled: true
            repo: git@github.com:bradfordwagner/deploy-argocd.git
            version: main
      gtk_clusters:
        dev:
          enabled: true
          labels:
            kubernetes.cnp.io/environment: dev
            kubernetes.cnp.io/cluster.jurisdiction: k3d
            kubernetes.cnp.io/cluster.region: muse2
            kubernetes.cnp.io/cluster.segment: multitenant
        admin:
          enabled: true
          labels: {}
          git_ops:
            namespace: argocd
            port: "8080"
            manifest_path: "{{ ansible_env.HOME }}/deploy_argocd"
            credentials:
              username: admin
              password: admin1234
```

See `test.yml` for a more complete example, including per-cluster `certs`.

## Testing

`test.yml` is run against the OS/arch build matrix defined in `config.yaml` via GitHub Actions (`.github/workflows/container_branches.yml` and `container_tags.yml`), using the [`bradfordwagner/dagger-container-builds`](https://github.com/bradfordwagner/dagger-container-builds) Dagger module. It asserts the installed binaries (`gitops-toolkit`, `kubectl`, `argocd`) are runnable and that the rendered `~/.gitops-toolkit-clusters.yaml` matches `tests/expected.clusters.yaml`.

## License

Apache-2.0

## Author Information

Bradford Wagner
