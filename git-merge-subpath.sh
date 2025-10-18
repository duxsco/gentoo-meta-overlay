#!/usr/bin/env bash

# Credits for "actual_path" and "script_dir":
# https://sqlpey.com/bash/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script-itself/#solution-9-readlink--f-with-bash_source
actual_path=$(readlink -f "${BASH_SOURCE[0]}")
script_dir=$(dirname "$actual_path")

packages_yml="$script_dir/packages.yml"

if grep -q '(https://github.com/mikefarah/yq/)' < <(yq --version); then
    packages_json=$(yq -o json "$packages_yml" | jq --compact-output .)
else
    packages_json=$(yq --compact-output . "$packages_yml")
fi

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
    if PATCH=$(git diff --color=never "$OLD_TREEISH" "$SOURCE_COMMIT:$GENTOO_PACKAGE") && [[ -n "${PATCH}" ]]; then
        if git apply -3 --directory="$GENTOO_PACKAGE" <<<"${PATCH}"; then
            # Don't change the first (Merge...) and last (${FUNCNAME[0]}:...) line of the commit message.
            git commit --no-gpg-sign -m "\
Merge Gentoo package \"$GENTOO_PACKAGE\" as existent in:

- Commit: $SOURCE_SHA1
- Git repository: $URL

${FUNCNAME[0]}: $SOURCE_SHA1 $GENTOO_PACKAGE"
        fi
    fi
}

readarray -t overlays < <(jq -r '.overlays | select(length > 0) | keys[]' <<< "$packages_json")

for overlay in "${overlays[@]}"; do

    # If the overlay is used by at least one of the packages...
    # shellcheck disable=SC2016
    if jq --arg overlay "$overlay" --exit-status '.packages[] | select(. == $overlay)' <<< "$packages_json" >/dev/null 2>&1; then

        # shellcheck disable=SC2016
        url=$(jq --arg overlay "$overlay" -r '.overlays[$overlay].url' <<< "$packages_json")

        # shellcheck disable=SC2016
        branch=$(jq --arg overlay "$overlay" -r '.overlays[$overlay].branch' <<< "$packages_json")

        # Make sure that the URL defined in the YAML is always set
        if git remote get-url "$overlay" >/dev/null 2>&1; then
            git remote set-url "$overlay" "$url"
        else
            git remote add "$overlay" "$url"
        fi

        git fetch --no-tags "$overlay" "$branch"
    fi
done

readarray -t package_names_from_yml_file < <(jq -r '.packages | select(length > 0) | keys[]' <<< "$packages_json" | sort -u)

for package in "${package_names_from_yml_file[@]}"; do
    # shellcheck disable=SC2016
    overlay=$(jq --arg package "$package" -r '.packages[$package]' <<< "$packages_json")
    # shellcheck disable=SC2016
    url=$(jq --arg overlay "$overlay" -r '.overlays[$overlay].url' <<< "$packages_json")
    # shellcheck disable=SC2016
    branch=$(jq --arg overlay "$overlay" -r '.overlays[$overlay].branch' <<< "$packages_json")

    git-merge-subpath "$overlay/$branch" "$package" "$url"
done

pushd "$(git rev-parse --show-toplevel)" || exit 1

readarray -t package_names_from_own_git_tree < <(git ls-files --full-name '*.ebuild' | xargs dirname | sort -u )

readarray -t obsolete_packages < <(
    comm --check-order -13 \
        <(printf '%s\n' "${package_names_from_yml_file[@]}") \
        <(printf '%s\n' "${package_names_from_own_git_tree[@]}")
)

for package in "${obsolete_packages[@]}"; do
    git rm -r -- "${package}" && \
    git commit --no-gpg-sign -m "Delete Gentoo package \"${package}\""
done

popd || exit 1
