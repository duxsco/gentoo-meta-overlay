#!/usr/bin/env bash

# Credits for function "git-merge-subpath()":
# https://stackoverflow.com/a/30386041

function git-merge-subpath() {
    # Friendly parameter names; strip any trailing slashes from Gentoo package.
    local SOURCE_COMMIT="$1" GENTOO_PACKAGE="${2%/}" URL="$3"

    local SOURCE_SHA1
    SOURCE_SHA1=$(git rev-parse --verify "$SOURCE_COMMIT^{commit}") || return 1

    local OLD_SHA1 GIT_ROOT
    GIT_ROOT=$(git rev-parse --show-toplevel)
    if [[ -n "$(ls -A "$GIT_ROOT/$GENTOO_PACKAGE" 2> /dev/null)" ]]; then
        # OLD_SHA1 will remain empty if there is no match.
        local RE="^${FUNCNAME[0]}: [0-9a-f]{40} $GENTOO_PACKAGE\$"
        OLD_SHA1=$(git log -1 --format=%b -E --grep="$RE" | \
                   grep --color=never -E "$RE" | tail -1 | awk '{print $2}')
    fi

    local OLD_TREEISH
    if [[ -n $OLD_SHA1 ]]; then
        OLD_TREEISH="$OLD_SHA1:$GENTOO_PACKAGE"
    else
        # This is the first time git-merge-subpath is run, so diff against the
        # empty commit instead of the last commit created by git-merge-subpath.
        OLD_TREEISH=$(git hash-object -t tree /dev/null)
    fi

    local PATCH
    if PATCH="$(git diff --color=never "$OLD_TREEISH" "$SOURCE_COMMIT:$GENTOO_PACKAGE")" && [[ -n "${PATCH}" ]]; then
        if git apply -3 --directory="$GENTOO_PACKAGE" <<<"${PATCH}"; then
            git commit --no-gpg-sign -m "\
Merge Gentoo package \"$GENTOO_PACKAGE\" provided:
- by commit: $SOURCE_SHA1
- in Git repository: $URL

Leave next line untouched!
${FUNCNAME[0]}: $SOURCE_SHA1 $GENTOO_PACKAGE"
        fi
    fi
}

readarray -t overlays < <(yq -r '.overlays | select(length > 0) | keys[]' packages.yml)

for overlay in "${overlays[@]}"; do

    # If the overlay is used by at least one of the packages...
    # shellcheck disable=SC2016
    if yq --arg overlay "$overlay" --exit-status '.packages[] | select(. == $overlay)' packages.yml >/dev/null 2>&1; then

        # shellcheck disable=SC2016
        url=$(yq --arg overlay "$overlay" -r '.overlays[$overlay].url' packages.yml)

        # shellcheck disable=SC2016
        branch=$(yq --arg overlay "$overlay" -r '.overlays[$overlay].branch' packages.yml)

        # Make sure that the URL defined in the YAML is always set
        if git remote get-url "$overlay" >/dev/null 2>&1; then
            git remote set-url "$overlay" "$url"
        else
            git remote add "$overlay" "$url"
        fi

        git fetch --no-tags "$overlay" "$branch"
    fi
done

readarray -t packages < <(yq -r '.packages | select(length > 0) | keys[]' packages.yml)

for package in "${packages[@]}"; do
    # shellcheck disable=SC2016
    overlay=$(yq --arg package "$package" -r '.packages[$package]' packages.yml)
    # shellcheck disable=SC2016
    url=$(yq --arg overlay "$overlay" -r '.overlays[$overlay].url' packages.yml)
    # shellcheck disable=SC2016
    branch=$(yq --arg overlay "$overlay" -r '.overlays[$overlay].branch' packages.yml)

    git-merge-subpath "$overlay/$branch" "$package" "$url"
done
