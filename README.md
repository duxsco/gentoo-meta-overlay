# Gentoo Meta Overlay (WIP)

This project enables you to manage your own Gentoo Linux overlay by cherry-picking from 3rd party overlays and introducing their packages to your overlay via pull request created by a GitHub Actions workflow. It basically does following using Git while removing all extraneous - not defined in [packages.yml](https://github.com/duxsco/gentoo-meta-overlay/blob/main/packages.yml) - local packages:

```shell
❯ rsync --delete --recursive --relative \
    <3rd party overlay>/./{<categoryA>/<packageA>,<categoryA>/<packageB>,<categoryC>/<packageD>} \
    <your overlay>/

❯ tree
.
├── <categoryA>
│   ├── <packageA>
│   │   └── packageA-1.2.3.ebuild
│   └── <packageB>
│       ├── packageB-2.1.42-r1.ebuild
│       └── packageB-2.2.0.ebuild
├── <categoryC>
│   └── <packageD>
│       └── packageD-0.1-r8.ebuild
├── metadata
│   └── layout.conf
└── profiles
    ├── eapi
    └── repo_name

8 directories, 7 files
```

## Fork & GitHub Actions

Steps you need to undertake for setup:

1. Create a fork containing only the branch "main" of [https://github.com/duxsco/gentoo-meta-overlay](https://github.com/duxsco/gentoo-meta-overlay)
2. Execute following commands [to create an overlay skeleton](https://wiki.gentoo.org/wiki/Handbook:AMD64/Portage/CustomTree#Alternative:_Manual_creation) in the branch "overlay":

```shell
# Create an empty branch named "overlay"
git switch --orphan overlay

# Create folders required for the overlay
mkdir metadata profiles

# Pick a sensible name for the repository
echo 'localrepo' > profiles/repo_name

# Define the EAPI used for the profiles within the repository
echo '8' > profiles/eapi

# Tell Portage that the repository master is the main Gentoo ebuild repo
# Thin manifest: https://wiki.gentoo.org/wiki/Repository_format/package/Manifest#Thin_manifest
echo -e 'masters = gentoo\nthin-manifests = true' > metadata/layout.conf

# You should have:
# ❯ tree
# .
# ├── metadata
# │   └── layout.conf
# └── profiles
#     ├── eapi
#     └── repo_name
#
# 3 directories, 3 files
#
# ❯ head -n 999 */*
# ==> metadata/layout.conf <==
# masters = gentoo
# thin-manifests = true
#
# ==> profiles/eapi <==
# 8
#
# ==> profiles/repo_name <==
# localrepo

# Commit the branch
git add metadata profiles
git commit -m "Create overlay skeleton"

# Push the branch "overlay"
git push -u origin overlay

# Switch back to the branch "main"
git switch main
```

3. Change `packages.yml` to your liking, commit and push the branch "main".
4. Make sure that a checkmark is set at "Allow GitHub Actions to create and approve pull requests" (see [link #1](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#preventing-github-actions-from-creating-or-approving-pull-requests) and [link #2](https://github.blog/changelog/2022-05-03-github-actions-prevent-github-actions-from-creating-and-approving-pull-requests/)).
5. Run GitHub Actions workflow from branch "main"
6. I recommend the use of [pram](https://github.com/gentoo/pram) to merge the pull request:

```shell
git switch overlay
pram --no-signoff --part-of --repository foo/gentoo 123
pram --no-signoff --part-of --repository https://github.com/foo/gentoo/pull/123
```

## Overlay Installation On Hosts

You need to execute following commands to setup the overlay on your hosts:

```shell
# Replace "duxsco" with the name
# you have set above in file "profiles/repo_name"
overlay_name="duxsco"

# Set your own GitHub overlay repository
git_repo="https://github.com/duxsco/gentoo-meta-overlay.git"

# Create folder for overlay
mkdir "/var/db/repos/${overlay_name}"

# Change ownership to avoid future syncs to run as root
chown portage:portage "/var/db/repos/${overlay_name}"

# Create overlay configuration folder
mkdir -p /etc/portage/repos.conf

# Save overlay configuration
echo "\
[${overlay_name}]
location = /var/db/repos/${overlay_name}
auto-sync = yes

sync-type = git
sync-uri = ${git_repo}

# The overlay isn't located in the default branch, but in branch \"overlay\".
sync-git-clone-extra-opts = --branch overlay

# It's optional, but recommended to OpenPGP sign your Git commits.
sync-git-verify-commit-signature = yes
sync-openpgp-key-path = /usr/share/openpgp-keys/${overlay_name}.asc" \
> "/etc/portage/repos.conf/${overlay_name}.conf"

# If you decided in favour of OpenPGP signature verification via Git,
# save your OpenPGP public key at /usr/share/openpgp-keys/${overlay_name}.asc
# and execute:
chown root:root "/usr/share/openpgp-keys/${overlay_name}.asc"
chmod u=rw,go=r "/usr/share/openpgp-keys/${overlay_name}.asc"
```
