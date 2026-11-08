"""Create an isolated CLI copy. The source checkout and installed CLI stay intact."""
import argparse
import pathlib
import shutil


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise ValueError(f"Expected exactly one integration point: {before[:100]!r}")
    return text.replace(before, after, 1)


def build_overlay(source, destination):
    source = source.resolve()
    destination = destination.resolve()
    if destination == source or source.is_relative_to(destination) or destination.is_relative_to(source):
        raise ValueError("Use a destination outside the source checkout")
    destination.mkdir(parents=True, exist_ok=True)
    if (destination / "bin").exists():
        raise ValueError("The destination already has a CLI")
    shutil.copytree(source / "bin", destination / "bin")
    library = destination / "bin/git-review-lib.sh"
    text = library.read_text(encoding="utf-8")
    start = text.index("} | od -An -v -tu1 | LC_ALL=C awk '")
    end = text.index("\n\t\t'\n\t)", start) + len("\n\t\t'")
    text = text[:start] + '} | "$GIT_REVIEW_META_HELPER" encode' + text[end:]
    text += r'''

# Experimental only: target discovery still uses Git at each write phase.
review_meta_config_path() {
    if [ "@D@{GIT_CONFIG+x}" = x ]; then
        printf '%s' "$GIT_CONFIG"
    else
        git rev-parse --git-path config
    fi
}

review_meta_header() {
    if [ "$_meta_emit_mode" = native ]; then
        printf '%s\000' git-review-meta-write-v1 "$1"
    fi
}
review_meta_footer() {
    if [ "$_meta_emit_mode" = native ]; then printf '%s\000' end; fi
}
review_meta_set() {
    if [ "$_meta_emit_mode" = native ]; then printf '%s\000' set "$1" "$2"
    else git config "$1" "$2"
    fi
}
review_meta_unset() {
    if [ "$_meta_emit_mode" = native ]; then printf '%s\000' unset "$1" ''
    else git config --unset "$1" || true
    fi
}
review_meta_run() {
    _meta_emit_mode=native
    if "$@" | "$GIT_REVIEW_META_HELPER" apply; then return 0
    else _meta_batch_status=$?
    fi
    # Only 78 promises no publication. A failed/uncertain commit is never retried.
    if [ "$_meta_batch_status" -ne 78 ]; then return "$_meta_batch_status"; fi
    _meta_emit_mode=git
    "$@"
}
'''.replace("@D@", "$")
    before = '''\tif [ -n "$cc_context" ]; then git config "branch.$_ct_target.reviewcommentscontext" "$cc_context" || return 1
\telse git config --unset "branch.$_ct_target.reviewcommentscontext" || true
\tfi
\tgit config "branch.$_ct_target.reviewcommentssession" "$cc_session" || return 1
\tgit config "branch.$_ct_target.reviewcommentsowner" "$cc_owner"'''
    after = r'''\tif [ "@D@{_review_meta_batch_save:-0}" -eq 1 ]; then
        _ct_config=$(review_meta_config_path) || return 1
        # shellcheck disable=SC2329 # Passed to review_meta_run below.
        _ct_meta_plan() {
            review_meta_header "$_ct_config" || return 1
            if [ -n "$cc_context" ]; then
                review_meta_set "branch.$_ct_target.reviewcommentscontext" "$cc_context" || return 1
            else
                review_meta_unset "branch.$_ct_target.reviewcommentscontext" || return 1
            fi
            review_meta_set "branch.$_ct_target.reviewcommentssession" "$cc_session" || return 1
            review_meta_set "branch.$_ct_target.reviewcommentsowner" "$cc_owner" || return 1
            review_meta_footer
        }
        review_meta_run _ct_meta_plan
    else
''' + before + "\n    fi"
    after = after.replace(r"\t", "\t").replace("@D@", "$")
    text = replace_once(text, before, after)
    library.write_text(text, encoding="utf-8", newline="\n")

    save = destination / "bin/git-review-verbs/save"
    text = save.read_text(encoding="utf-8")
    source_line = '. "' + "$" + '{GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh"\n'
    text = replace_once(text, source_line, source_line + "\n_review_meta_batch_save=1\n")
    text = replace_once(text, '\t\tgit config "branch.$saved.$1" "$v"',
                        '\t\treview_meta_set "branch.$saved.$1" "$v" || return 1')
    blocks = [
        '\tgit config "branch.$saved.reviewmode" step\n\tcopy_meta reviewstart\n\tcopy_meta reviewcount\n\tcopy_meta reviewstep\n',
        '\tgit config "branch.$saved.reviewsavedlower" "$lower"\n',
        '\t\tgit config "branch.$saved.reviewmode" walk\n\t\tcopy_meta reviewwalkstep\n\t\tcopy_meta reviewwalkcount\n\t\tcopy_meta reviewwalkkeys\n\t\tcopy_meta reviewwalkfromdraft\n\t\tcopy_meta reviewwalkbase\n',
        '\t\tgit config "branch.$saved.reviewmode" whole\n',
    ]
    for block in blocks:
        text = replace_once(text, block, "")
    prefix = r'''# Metadata common to both modes.
_save_meta_config=$(review_meta_config_path) || exit 1
_save_meta_plan() {
review_meta_header "$_save_meta_config" || return 1
if [ "$mode" = step ]; then
    review_meta_set "branch.$saved.reviewmode" step || return 1
    copy_meta reviewstart || return 1
    copy_meta reviewcount || return 1
    copy_meta reviewstep || return 1
else
    review_meta_set "branch.$saved.reviewsavedlower" "$lower" || return 1
    if [ "$mode" = walk ]; then
        review_meta_set "branch.$saved.reviewmode" walk || return 1
        copy_meta reviewwalkstep || return 1
        copy_meta reviewwalkcount || return 1
        copy_meta reviewwalkkeys || return 1
        copy_meta reviewwalkfromdraft || return 1
        copy_meta reviewwalkbase || return 1
    else
        review_meta_set "branch.$saved.reviewmode" whole || return 1
    fi
fi'''
    text = replace_once(text, "# Metadata common to both modes.", prefix)
    text = replace_once(text, 'git config "branch.$saved.reviewreturn" "$target"',
                        r'''review_meta_set "branch.$saved.reviewreturn" "$target" || return 1
review_meta_footer
}
review_meta_run _save_meta_plan || exit 1''')
    # These original common-copy calls now execute inside a conditional function.
    # Keep their errors explicit instead of relying on errexit inside a function.
    import re
    text = re.sub(r"^(copy_meta [a-z]+)$", r"\1 || return 1", text, flags=re.MULTILINE)
    save.write_text(text, encoding="utf-8", newline="\n")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    print(build_overlay(args.source, args.destination))
