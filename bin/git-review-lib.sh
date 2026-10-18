#!/usr/bin/env sh
#
# git-review-lib.sh — helpers shared by the git review verbs. *Sourced, never
# run*: the verbs load it as "${GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh", a path
# the git-review dispatcher exports before exec'ing the verb, pointing at the
# libexec directory where it, this lib and git-review-verbs/ live together (never
# on PATH). It only defines functions, so sourcing it has no side effects.

# shellcheck disable=SC2030,SC2031
# Porcelain emitters deliberately stage records in a subshell; mutations reload
# their own state and never depend on assignments made while staging output.

# ── Comments: identidad y almacenamiento privado ─────────────────────────────

# Tokens are opaque SHA-sized lowercase hex. Validate BEFORE joining any path;
# document paths never come from a branch name, label or source-code location.
comments_token_valid() {
	case "$1" in ''|*[!0-9a-f]*) return 1 ;; esac
	[ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}

comments_require_token() {
	comments_token_valid "$1" || {
		printf 'error: invalid comments context token\n' >&2
		return 1
	}
}

comments_error() { printf 'error: %s\n' "$*" >&2; return 1; }

# Check every existing component, including the root, without following links.
# Missing components are allowed for lazy creation; special files are never read.
comments_safe_path() {
	case "$1" in
		"$cm_root"|"$cm_root/"*) ;;
		*) comments_error "unsafe comments path: $1"; return 1 ;;
	esac
	case "$1/" in *'/../'*|*'/./'*|*'//'*) comments_error "unsafe comments path: $1"; return 1 ;; esac
	_csp_at=$cm_root
	_csp_rest=${1#"$cm_root"}
	_csp_rest=${_csp_rest#/}
	while :; do
		if [ -L "$_csp_at" ] || { [ -e "$_csp_at" ] && [ ! -f "$_csp_at" ] && [ ! -d "$_csp_at" ]; }; then
			comments_error "unsafe comments path: $_csp_at"; return 1
		fi
		[ -n "$_csp_rest" ] || break
		if [ -e "$_csp_at" ] && [ ! -d "$_csp_at" ]; then
			comments_error "unsafe comments path: $_csp_at"; return 1
		fi
		_csp_part=${_csp_rest%%/*}
		_csp_at=$_csp_at/$_csp_part
		if [ "$_csp_part" = "$_csp_rest" ]; then _csp_rest=''; else _csp_rest=${_csp_rest#*/}; fi
	done
}

# Manifests are data, never shell. Duplicate keys and unsafe file types fail.
comments_field() {
	comments_safe_path "$1" || return 1
	if [ -e "$1" ] && [ ! -f "$1" ]; then comments_error "unsafe comments path: $1"; return 1; fi
	[ -f "$1" ] || return 0
	awk -F '\t' -v key="$2" '$1 == key { n++; value=substr($0, length(key)+2) }
		END { if(n > 1) exit 1; if(n == 1) print value }' "$1"
}

comments_revision() {
	comments_safe_path "$1" || return 1
	if [ -f "$1" ]; then
		git hash-object --no-filters -- "$1"
	elif [ -e "$1" ]; then
		comments_error "unsafe comments path: $1"
	else
		printf 'absent\n'
	fi
}

# Read the capture state defensively, without materializing a context/session.
# Whole/walk use the real lower, step uses the selected commit and its parent.
# Identity always has its OWN full merge-base, independent of delta/--from.
comments_state() {
	cm_gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || { comments_error 'not a git repository'; return 1; }
	cm_root=$cm_gitdir/review-comments
	comments_safe_path "$cm_root" || return 1
	cm_branch=$(git symbolic-ref --quiet --short HEAD || true)
	cm_active=0 cm_source='' cm_target='' cm_tip='' cm_full_base=''
	cm_capture_base='' cm_capture_head='' cm_cursor='' cm_mode=whole cm_kind=review
	cm_context='' cm_session='' cm_dir='' cm_candidates='' cm_seed=0 cm_provisional=0 cm_recovery=0
	cm_identity=fresh cm_label='' cm_guard='' cm_capture_guard='' cm_scope=result
	case "$cm_branch" in
		review/*)
			cm_source=$(git config "branch.$cm_branch.reviewsource" || true)
			cm_tip=$(git config "branch.$cm_branch.reviewtip" || true)
			if [ -n "$cm_source" ] && [ -n "$cm_tip" ]; then cm_active=1; fi
			;;
	esac
	[ "$cm_active" -eq 1 ] || return 0
	comments_token_valid "$cm_tip" || { comments_error 'comments capture tip is not a full object ID'; return 1; }
	cm_scope=active cm_label=$cm_source
	cm_mode=$(git config "branch.$cm_branch.reviewmode" || true)
	cm_mode=${cm_mode:-whole}
	cm_target=$(git config "branch.$cm_branch.reviewbase" || true)
	_cm_lower=$(git rev-parse HEAD)
	if [ "$(git config "branch.$cm_branch.reviewreadonly" || true)" = 1 ]; then
		cm_kind=compare
		cm_full_base=$(git config "branch.$cm_branch.reviewstart" || true)
		cm_full_base=${cm_full_base:-$_cm_lower}
	elif [ -n "$cm_target" ]; then
		_cm_base_ref=$cm_target
		if ! git rev-parse --verify --quiet "$_cm_base_ref^{commit}" >/dev/null; then
			_cm_remote=$(git config reviewworkflow.remote || true)
			_cm_base_ref=${_cm_remote:-origin}/$cm_target
		fi
		cm_full_base=$(git merge-base "$_cm_base_ref" "$cm_tip" 2>/dev/null || true)
	fi
	cm_capture_base=$_cm_lower cm_capture_head=$cm_tip
	case "$cm_mode" in
		step)
			cm_cursor=$(git config "branch.$cm_branch.reviewstep" || true)
			_cm_start=$(git config "branch.$cm_branch.reviewstart" || true)
			case "$cm_cursor" in
				''|*[!0-9]*) cm_capture_base='' cm_capture_head='' ;;
				*)
					# rev-list is safe here: the step lower is required to be a commit.
					if git cat-file -e "$_cm_start^{commit}" 2>/dev/null; then
						cm_capture_head=$(git rev-list --reverse --first-parent --no-merges "$_cm_start..$cm_tip" | sed -n "${cm_cursor}p")
						cm_capture_base=$(git rev-parse --verify "$cm_capture_head^" 2>/dev/null || true)
					else cm_capture_base='' cm_capture_head=''
					fi
					;;
			esac
			;;
		walk) cm_cursor=$(git config "branch.$cm_branch.reviewwalkstep" || true) ;;
	esac
	_cm_phase=$(git config "branch.$cm_branch.reviewresume" || true)
	if [ "$_cm_phase" = conflict ]; then cm_capture_base='' cm_capture_head=''; fi
	cm_session=$(git config "branch.$cm_branch.reviewcommentssession" || true)
	cm_context=$(git config "branch.$cm_branch.reviewcommentscontext" || true)
	_cm_owner=$(git config "branch.$cm_branch.reviewcommentsowner" || true)
	if [ -n "$_cm_owner" ] && [ "$_cm_owner" != "$cm_gitdir" ]; then
		comments_error 'comments session belongs to another gitdir'; return 1
	fi
	if [ -z "$cm_session" ] && [ -n "$cm_context$_cm_owner" ]; then
		comments_error 'comments session ownership metadata is incomplete'; return 1
	fi
	if [ -n "$cm_session" ]; then
		comments_require_token "$cm_session" || return 1
		if [ -n "$cm_context" ]; then comments_require_token "$cm_context" || return 1; fi
		cm_dir=$cm_root/sessions/$cm_session
		_cm_manifest=$cm_dir/manifest
		_cm_manifest_owner=$(comments_field "$_cm_manifest" owner_gitdir) || return 1
		_cm_manifest_context=$(comments_field "$_cm_manifest" context) || return 1
		_cm_custodian=$(comments_field "$_cm_manifest" custodian) || return 1
		_cm_manifest_session=$(comments_field "$_cm_manifest" session) || return 1
		if [ "$_cm_manifest_session" != "$cm_session" ] || [ "$_cm_manifest_owner" != "$cm_gitdir" ] || [ "$_cm_manifest_context" != "$cm_context" ] || [ "$_cm_custodian" != "$cm_branch" ]; then
			comments_error 'comments session ownership does not match'; return 1
		fi
		if [ -n "$cm_context" ]; then cm_identity=resolved
		else
			cm_provisional=1
			if [ -n "$cm_full_base" ]; then cm_full_base=$(comments_field "$_cm_manifest" full_base) || return 1; fi
			comments_context_resolve || return 1
		fi
	else
		comments_context_resolve || return 1
	fi
	cm_capture_guard=$(comments_capture_signature) || return 1
	cm_guard=$(printf '%s\000' "$cm_capture_guard" "$cm_context" "$cm_session" "$_cm_owner" | git hash-object --stdin)
	if [ -z "$cm_session" ] && [ "$cm_identity" = resolved ]; then
		# A legacy review has not copied its discard boundary yet. Report only
		# absent prospective preparation paths; never let an editor change the
		# retained result which abort is required to preserve.
		cm_dir=$cm_root/sessions/$cm_guard
	fi
}

# Own initialization changes context/session metadata, never the capture state.
# Keep the latter separately so a cursor move during lazy copying is detected.
comments_capture_signature() {
	printf '%s\000' "$cm_gitdir" "$cm_branch" "$cm_source" "$cm_target" "$cm_tip" "$cm_full_base" "$cm_kind" "$cm_mode" "$cm_cursor" "$cm_capture_base" "$cm_capture_head" "$_cm_phase" | git hash-object --stdin
}

# Portable identity is read from the preamble only. The contour parser handles
# entry fences; this marker reader refuses duplicates instead of guessing.
comments_marker() {
	git show "$1:.review/comments.md" 2>/dev/null | walk_normalize | comments_contours marker
}

comments_context_resolve() {
	cm_context='' cm_candidates='' cm_seed=0 cm_identity=fresh
	[ -n "$cm_full_base" ] || { cm_identity=ambiguous; return 0; }
	_cm_portable=''
	if [ "$cm_kind" = review ]; then
		_cm_tip_marker=$(comments_marker "$cm_tip")
		_cm_base_marker=$(comments_marker "$cm_full_base")
		if [ -n "$_cm_tip_marker" ] && ! comments_token_valid "$_cm_tip_marker"; then
			cm_identity=ambiguous; return 0
		fi
		if [ -n "$_cm_tip_marker" ] && [ "$_cm_tip_marker" != "$_cm_base_marker" ]; then
			_cm_portable=$_cm_tip_marker
		fi
		_cm_tip_blob=$(git rev-parse --verify "$cm_tip:.review/comments.md" 2>/dev/null || true)
		_cm_base_blob=$(git rev-parse --verify "$cm_full_base:.review/comments.md" 2>/dev/null || true)
		# shellcheck disable=SC2034 # Seed selection is consumed by init/add.
		if [ -n "$_cm_tip_blob" ] && [ "$_cm_tip_blob" != "$_cm_base_blob" ] && { [ -z "$_cm_tip_marker" ] || [ -n "$_cm_portable" ]; }; then cm_seed=1; fi
	fi
	_cm_continuations='' _cm_incompatible=0 _cm_count=0
	comments_safe_path "$cm_root/contexts" || return 1
	for _cm_manifest in "$cm_root"/contexts/*/manifest; do
		[ -e "$_cm_manifest" ] || [ -L "$_cm_manifest" ] || continue
		_cm_token=${_cm_manifest%/manifest}; _cm_token=${_cm_token##*/}
		comments_require_token "$_cm_token" || return 1
		_cm_kind=$(comments_field "$_cm_manifest" kind) || return 1
		_cm_source=$(comments_field "$_cm_manifest" source) || return 1
		_cm_target=$(comments_field "$_cm_manifest" target) || return 1
		if [ "$_cm_kind" != "$cm_kind" ] || [ "$_cm_source" != "$cm_source" ] || [ "$_cm_target" != "$cm_target" ]; then continue; fi
		_cm_last=$(comments_field "$_cm_manifest" last_tip) || return 1
		_cm_full=$(comments_field "$_cm_manifest" full_base) || return 1
		_cm_retained=$(comments_result_dir "$_cm_token") || return 1
		if [ -n "$_cm_retained" ]; then
			_cm_retained_tip=$(comments_field "$_cm_retained/manifest" last_tip) || return 1
			_cm_retained_base=$(comments_field "$_cm_retained/manifest" full_base) || return 1
			if [ -n "$_cm_retained_tip" ]; then _cm_last=$_cm_retained_tip; fi
			if [ -n "$_cm_retained_base" ]; then _cm_full=$_cm_retained_base; fi
		fi
		if [ "$cm_kind" = compare ]; then
			if [ "$_cm_last" != "$cm_tip" ] || [ "$_cm_full" != "$cm_full_base" ]; then continue; fi
		else
			if git merge-base --is-ancestor "$_cm_last" "$cm_full_base" 2>/dev/null; then continue; fi
		fi
		cm_candidates="${cm_candidates}${cm_candidates:+
}$_cm_token"
		if [ "$cm_kind" = compare ] || git merge-base --is-ancestor "$_cm_last" "$cm_tip" 2>/dev/null; then
			_cm_continuations=$_cm_token
			_cm_count=$((_cm_count + 1))
		else _cm_incompatible=1
		fi
	done
	if [ -n "$_cm_portable" ]; then
		cm_context=$_cm_portable cm_identity=resolved
		if [ "$_cm_incompatible" -eq 1 ] || [ "$_cm_count" -gt 1 ] || { [ "$_cm_count" -eq 1 ] && [ "$_cm_continuations" != "$_cm_portable" ]; }; then
			cm_identity=ambiguous cm_context=''
		fi
	elif [ "$_cm_count" -eq 1 ] && [ "$_cm_incompatible" -eq 0 ]; then
		cm_context=$_cm_continuations cm_identity=resolved
	elif [ "$_cm_count" -gt 0 ] || [ "$_cm_incompatible" -eq 1 ]; then cm_identity=ambiguous
	fi
}

# A single contour reader shared by count and the later entry transformations.
# No object resolution per entry, and no assumption that visible numbers are IDs.
comments_scan() {
	comments_safe_path "$1" || return 1
	[ -f "$1" ] || return 1
	walk_normalize <"$1" | comments_contours count
}

comments_contours() {
	awk -v operation="$1" -v original="${2:-}" -v final_lf="${3:-1}" '
		BEGIN { if(original!="") {while((getline rawline < original)>0) raw[++rawcount]=rawline; close(original)} }
		function oid(s) {return (length(s)==40 || length(s)==64) && s !~ /[^0-9a-f]/}
		function positive(s) {return s ~ /^[0-9]+$/ && s !~ /^0+$/}
		function ordered(a,b) {
			sub(/^0+/,"",a);sub(/^0+/,"",b)
			return length(a)<length(b) || (length(a)==length(b) && ("x" a)<=("x" b))
		}
		function encoded_path(s,    i,e) {
			if(s ~ /[\t\r\n>]/) return 0
			if(s ~ /^\// || s ~ /\/\// || s ~ /(^|\/)\.\.?($|\/)/) return 0
			for(i=1;i<=length(s);i++) if(substr(s,i,1)=="%") {
				e=substr(s,i,3)
				if(e!="%25" && e!="%09" && e!="%0D" && e!="%0A" && e!="%3E") return 0
				i+=2
			}
			return 1
		}
		function emitraw(isentry,    emit,start,digits) {
			if(operation!="renumber") return
			emit=raw[NR]
			if(isentry) {
				start=index(emit,"## ")+3; digits=substr(emit,start)
				match(digits,/^[0-9]+/)
				emit=substr(emit,1,start-1) count substr(digits,RLENGTH+1)
			}
			printf "%s",emit; if(NR<rawcount || final_lf==1) printf "\n"
		}
		function flushmeta(    key) {
			if(!metadata) return
			if((values["base"]!="" || values["head"]!="") && (!oid(values["base"]) || !oid(values["head"]))) badmeta=1
			if(values["side"]!="" && values["side"]!="base" && values["side"]!="head") badmeta=1
			if(values["side"]=="base" && values["base-path"]=="") badmeta=1
			if(values["side"]=="head" && values["head-path"]=="") badmeta=1
			if(keys["start"] || keys["end"]) {
				if(!positive(values["start"]) || !positive(values["end"]) || !ordered(values["start"],values["end"]) || values["side"]=="") badmeta=1
			}
			if(keys["unversioned"] && values["unversioned"]!="1") badmeta=1
			if(!encoded_path(values["base-path"]) || !encoded_path(values["head-path"])) badmeta=1
			if(badmeta) printf "comment-diagnostic\t%d\tmetadata\tComment location metadata is incomplete or invalid.\n",count
			else {
				if(values["base"]!="") printf "comment-version\t%d\t%s\t%s\n",count,values["base"],values["head"]
				if(values["base-path"]!="") printf "comment-path\t%d\tbase\t%s\n",count,values["base-path"]
				if(values["head-path"]!="") printf "comment-path\t%d\thead\t%s\n",count,values["head-path"]
				if(values["start"]!="" && values["end"]!="") printf "comment-location\t%d\t%s\t%s\t%s\n",count,values["side"],values["start"],values["end"]
				if(values["unversioned"]=="1") printf "comment-unversioned\t%d\n",count
			}
			for(key in values) delete values[key]
			for(key in keys) delete keys[key]
			metadata=0; badmeta=0
		}
		function fence(s,    c,i) {
			# The caller stripped at most three spaces explicitly; interval
			# expression support differs across POSIX awk implementations.
			c=substr(s,1,1); if(c!="`" && c!="~") return 0
			for(i=1; substr(s,i,1)==c; i++) {}
			fc=c; fl=i-1; rest=substr(s,i)
			return fl>=3
		}
		{
			line=$0; s=line; isentry=0
			for(sp=0; sp<3 && substr(s,1,1)==" "; sp++) s=substr(s,2)
			if(infence) {
				if(fence(s) && fc==openchar && fl>=openlen && rest ~ /^[ \t]*$/) infence=0
				emitraw(0); next
			}
			if(!html && fence(s) && (fc!="`" || index(rest,"`")==0)) {
				infence=1; openchar=fc; openlen=fl; emitraw(0); next
			}
			if(operation=="marker" && count==0) {
				if(!html && line=="<!-- git-review-comments v1") marker=1
				else if(!html && line ~ /^<!-- git-review-comments /) badmarker=1
				else if(marker && line ~ /^context /) {markers++; token=substr(line,9)}
				if(marker && line=="-->") marker=0
			}
			if(!html && line ~ /^## [0-9]+\.[ \t]*/) {
				count++; isentry=1; headingline=NR; metadata_allowed=1
				if(operation=="entries") {
					number=line; sub(/^## /,"",number); sub(/\..*$/,"",number)
					title=line; sub(/^## [0-9]+\.[ \t]*/,"",title)
					printf "comment-entry\t%d\t%s\t%d\t%s\n",count,number,NR,title
				}
			}
			if(operation=="entries") {
				if(!html && metadata_allowed && (NR==headingline+1 || NR==headingline+2) && line ~ /^<!-- git-review-comment /) {
					metadata=1; if(line!="<!-- git-review-comment v1") badmeta=1
				}
				else if(metadata && line=="-->") flushmeta()
				else if(metadata) {
					p=index(line," "); if(p<2) badmeta=1
					else {key=substr(line,1,p-1); if(keys[key]++) badmeta=1; values[key]=substr(line,p+1)}
				}
				else if(NR==headingline+1 && line !~ /^[ \t]*$/) metadata_allowed=0
			}
			while(length(s)) {
				if(html) {
					p=index(s,"-->"); if(!p) break
					s=substr(s,p+3); html=0
				} else {
					p=index(s,"<!--"); if(!p) break
					s=substr(s,p+4); html=1
				}
			}
			emitraw(isentry)
		}
		END {
			if(operation=="marker") {
				if(badmarker || markers>1 || marker) print "invalid"
				else if(markers==1 && !html) print token
			} else if(operation=="entries" || operation=="renumber") {
				if(html) exit 1
			} else {
				if(html) exit 1
				if(operation=="append" && infence) exit 1
				if(operation=="input" && (infence || count>0)) exit 1
				print count+0
			}
		}
	'
}

comments_result_dir() {
	comments_require_token "$1" || return 1
	_crd_current=$cm_root/results/$1/current
	comments_safe_path "$_crd_current" || return 1
	[ -f "$_crd_current" ] || return 0
	_crd_generation=$(cat "$_crd_current") || return 1
	comments_require_token "$_crd_generation" || return 1
	comments_safe_path "$cm_root/results/$1/$_crd_generation/manifest" || return 1
	[ -f "$cm_root/results/$1/$_crd_generation/manifest" ] || { comments_error 'incomplete comments generation'; return 1; }
	printf '%s\n' "$cm_root/results/$1/$_crd_generation"
}

comments_emit_document() {
	_ced_path=$cm_dir/$1.md
	if ! _ced_revision=$(comments_revision "$_ced_path" 2>/dev/null); then
		# An unavailable byte revision must not look like an empty document.
		# It is deliberately unusable as a write guard; the other row survives.
		porcelain_row comments-document "$_ced_path" "$cm_context" "$1" present unreadable
		porcelain_row comments-diagnostic "$_ced_path" read 'The comments document could not be read safely.'
		return 0
	fi
	_ced_presence=present
	if [ "$_ced_revision" = absent ]; then _ced_presence=absent; fi
	porcelain_row comments-document "$_ced_path" "$cm_context" "$1" "$_ced_presence" "$_ced_revision"
	if [ "$_ced_presence" = present ]; then
		if _ced_count=$(comments_scan "$_ced_path"); then
			porcelain_row comments-count "$_ced_path" "$_ced_count"
			_ced_entries=$(walk_normalize <"$_ced_path" | comments_contours entries) || return 1
			printf '%s\n' "$_ced_entries" | COMMENTS_DIAGNOSTIC_PATH="$_ced_path" awk -F '\t' '$1=="comment-diagnostic" {printf "comments-diagnostic\t%s\t%s\t%s\n",ENVIRON["COMMENTS_DIAGNOSTIC_PATH"],$3,$4}'
		else
			porcelain_row comments-diagnostic "$_ced_path" format 'The document could not be read without ambiguous entry boundaries.'
		fi
	fi
	if [ "$1" = shared ] && [ -f "$cm_dir/source-conflict" ]; then
		porcelain_row comments-diagnostic "$_ced_path" source-conflict 'The source and retained Shared comments changed separately; both versions were preserved.'
	fi
}

# Enumerate retained results and paused preparations; never infer recency.
comments_stored_contexts() {
	comments_safe_path "$cm_root/results" || return 1
	for _csc_pointer in "$cm_root"/results/*/current; do
		[ -e "$_csc_pointer" ] || [ -L "$_csc_pointer" ] || continue
		_csc_token=${_csc_pointer%/current}; _csc_token=${_csc_token##*/}
		comments_require_token "$_csc_token" || return 1
		printf '%s\n' "$_csc_token"
	done
	_csc_branches=$(git for-each-ref --format='%(refname:short)' refs/heads/review-saved/) || return 1
	while IFS= read -r _csc_branch; do
		[ -n "$_csc_branch" ] || continue
		_csc_token=$(git config "branch.$_csc_branch.reviewcommentscontext" || true)
		[ -n "$_csc_token" ] || continue
		comments_require_token "$_csc_token" || return 1
		printf '%s\n' "$_csc_token"
	done <<EOF
$_csc_branches
EOF
	_csc_branches=$(git for-each-ref --format='%(refname:short)' refs/heads/review/) || return 1
	while IFS= read -r _csc_branch; do
		[ -n "$_csc_branch" ] || continue
		[ -n "$(git config "branch.$_csc_branch.reviewundoouthead" || true)" ] || continue
		_csc_token=$(git config "branch.$_csc_branch.reviewcommentscontext" || true)
		[ -n "$_csc_token" ] || continue
		comments_require_token "$_csc_token" || return 1
		printf '%s\n' "$_csc_token"
	done <<EOF
$_csc_branches
EOF
}

# A paused preparation is the editable version of its context. Its previous
# retained generation remains the discard boundary, not another editable row.
comments_load_stored() {
	cm_dir='' cm_scope=result cm_label=$cm_context cm_recovery=0
	_cstored_count=0
	_cstored_branches=$(git for-each-ref --format='%(refname:short)' refs/heads/review-saved/) || return 1
	while IFS= read -r _cstored_branch; do
		[ -n "$_cstored_branch" ] || continue
		[ "$(git config "branch.$_cstored_branch.reviewcommentscontext" || true)" = "$cm_context" ] || continue
		comments_preflight_branch "$_cstored_branch" || return 1
		cm_dir=$cc_dir cm_scope=saved cm_label=${_cstored_branch#review-saved/}
		_cstored_count=$((_cstored_count + 1))
	done <<EOF
$_cstored_branches
EOF
	_cstored_result=$(comments_result_dir "$cm_context") || return 1
	_cstored_retained_session=''
	if [ -n "$_cstored_result" ]; then _cstored_retained_session=$(comments_field "$_cstored_result/manifest" session) || return 1; fi
	if [ "$_cstored_count" -eq 0 ]; then
		_cstored_branches=$(git for-each-ref --format='%(refname:short)' refs/heads/review/) || return 1
		while IFS= read -r _cstored_branch; do
			[ -n "$_cstored_branch" ] || continue
			[ "$(git config "branch.$_cstored_branch.reviewcommentscontext" || true)" = "$cm_context" ] || continue
			[ -n "$(git config "branch.$_cstored_branch.reviewundoouthead" || true)" ] || continue
			_cstored_session=$(git config "branch.$_cstored_branch.reviewcommentssession" || true)
			[ "$_cstored_session" != "$_cstored_retained_session" ] || continue
			comments_preflight_branch "$_cstored_branch" || return 1
			cm_dir=$cc_dir cm_label=${_cstored_branch#review/} cm_recovery=1
			_cstored_count=$((_cstored_count + 1))
		done <<EOF
$_cstored_branches
EOF
	fi
	[ "$_cstored_count" -le 1 ] || { comments_error 'multiple preparations own this comments context'; return 1; }
	if [ -z "$cm_dir" ]; then cm_dir=$_cstored_result; fi
	[ -n "$cm_dir" ] || { comments_error 'comments context has no retained documents'; return 1; }
	cm_kind=$(comments_field "$cm_root/contexts/$cm_context/manifest" kind) || return 1
	if [ "$(comments_field "$cm_root/contexts/$cm_context/manifest" owner_gitdir)" != "$cm_gitdir" ]; then
		comments_error 'comments context belongs to another gitdir'; return 1
	fi
	cm_guard=$(printf '%s\000' "$cm_gitdir" "$cm_context" "$cm_dir" "$cm_scope" "$cm_label" | git hash-object --stdin)
}

comments_emit_context() {
	comments_require_token "$cm_context" || return 1
	comments_safe_path "$cm_root/contexts/$cm_context/manifest" || return 1
	if [ -z "$cm_dir" ]; then
		cm_dir=$(comments_result_dir "$cm_context") || return 1
		if [ -z "$cm_dir" ]; then
			# Known portable contexts have no local preparation yet. No directory
			# is created by reporting the future document locations.
			cm_dir=$cm_root/contexts/$cm_context
		fi
	fi
	if [ -z "$cm_guard" ]; then cm_guard=$(printf '%s\000' "$cm_gitdir" "$cm_context" "$cm_dir" | git hash-object --stdin); fi
	porcelain_row comments-context "$cm_context" "$cm_kind" "$cm_scope" "$cm_guard" "$cm_label"
	comments_emit_document local || return 1
	comments_emit_document shared || return 1
	if [ "$cm_recovery" -eq 1 ]; then
		porcelain_row comments-diagnostic "$cm_dir/shared.md" result-write 'The comments result could not be retained; its complete preparation remains available.'
	fi
	_cec_delivery=$(comments_field "$cm_dir/delivery" state) || return 1
	if [ -z "$_cec_delivery" ] && [ "$cm_scope" = active ] && [ "$cm_kind" = review ] && [ -f "$cm_dir/shared.md" ]; then
		comments_safe_path "$cm_dir/source-baseline.md" || return 1
		if ! comments_same_file "$cm_dir/shared.md" "$cm_dir/source-baseline.md"; then _cec_delivery=prepared; fi
	fi
	if [ -n "$_cec_delivery" ]; then porcelain_row comments-delivery "$cm_context" "$_cec_delivery" 'Shared comments delivery.'; fi
}

comments_status() {
	comments_state || return 1
	_cs_requested=$1 _cs_porcelain=$2
	if [ -n "$_cs_requested" ]; then
		comments_require_token "$_cs_requested" || return 1
		comments_revision "$cm_root/contexts/$_cs_requested/manifest" >/dev/null || return 1
		if [ "$_cs_requested" != "$cm_context" ]; then
			cm_context=$_cs_requested
			comments_load_stored || return 1
			cm_identity=resolved
		fi
	fi
	# Stage output in the shell, so unsafe metadata cannot yield a partial record
	# stream a client might mistakenly consume. No temporary file for a query.
	_cs_output=$(
		if [ "$cm_active" -eq 1 ]; then porcelain_row comments-guard "$cm_guard"; fi
		case "$cm_identity" in
			resolved) porcelain_row comments-identity resolved 'Comments context selected.' ;;
			ambiguous) porcelain_row comments-identity ambiguous 'Choose a comments context before writing.' ;;
			fresh) porcelain_row comments-identity fresh 'No comments context yet.' ;;
		esac
		if [ -n "$cm_context" ]; then comments_emit_context || exit 1
		elif [ "$cm_active" -eq 0 ]; then
			_cs_contexts=$(comments_stored_contexts) || exit 1
			_cs_contexts=$(printf '%s\n' "$_cs_contexts" | sort -u)
			while IFS= read -r cm_context; do
				[ -n "$cm_context" ] || continue
				comments_load_stored || exit 1
				comments_emit_context || exit 1
			done <<EOF
$_cs_contexts
EOF
		fi
		if [ "$cm_identity" = ambiguous ]; then
			printf '%s\n' "$cm_candidates" | while IFS= read -r _cs_candidate; do
				[ -n "$_cs_candidate" ] || continue
				porcelain_row comments-candidate "$_cs_candidate" "$cm_label"
			done
		fi
		if [ "$cm_active" -eq 1 ] && [ "$cm_scope" = active ] && [ -n "$cm_capture_base" ] && [ -n "$cm_capture_head" ]; then
			porcelain_row comments-capture "$cm_guard" "$cm_capture_base" "$cm_capture_head"
		fi
	) || return 1
	if [ "$_cs_porcelain" -eq 1 ]; then printf '%s\n' "$_cs_output"
	else
		printf '%s\n' "$_cs_output" | awk -F '\t' '
			$1=="comments-identity" { print $3 }
			$1=="comments-context" { print "Context: " $2 " (" $3 ", " $4 ")" }
			$1=="comments-document" { print $4 ": " $5 " — " $2 }
			$1=="comments-count" { print "Entries: " $3 }
			$1=="comments-diagnostic" { print $4 }
		'
	fi
}

# Mutation doors are shared by public handlers and the focused test driver.
# Ownership is not inferred from a lock's pid: unknown locks are never stolen.
comments_lock() {
	comments_require_token "$1" || return 1
	cm_lock=$cm_root/locks/$1.lock
	cm_lock_root=$cm_root cm_lock_parent=$cm_root/locks
	cm_lock_root_created=0 cm_lock_parent_created=0
	if [ ! -e "$cm_root" ]; then cm_lock_root_created=1; fi
	if [ ! -e "$cm_root/locks" ]; then cm_lock_parent_created=1; fi
	comments_safe_path "$cm_lock/owner" || return 1
	mkdir -p "$cm_root/locks" || { comments_error 'could not create comments lock directory'; return 1; }
	if ! mkdir "$cm_lock" 2>/dev/null; then comments_error 'comments context is locked'; return 1; fi
	cm_lock_owned=1
	if ! printf 'pid\t%s\nowner_gitdir\t%s\n' "$$" "$cm_gitdir" >"$cm_lock/owner"; then
		rmdir "$cm_lock" 2>/dev/null || true
		cm_lock_owned=0
		comments_error 'could not record comments lock owner'; return 1
	fi
}

comments_unlock() {
	if [ "${cm_lock_owned:-0}" -eq 1 ]; then
		# The path and file were created by this invocation; never recursively
		# remove a directory whose contents may now belong to somebody else.
		if [ ! -L "$cm_lock" ] && [ ! -L "$cm_lock/owner" ] && [ "$(comments_field "$cm_lock/owner" pid)" = "$$" ]; then
			rm -f "$cm_lock/owner"
			rmdir "$cm_lock" 2>/dev/null || true
		fi
		cm_lock_owned=0
		if [ "$cm_lock_parent_created" -eq 1 ]; then rmdir "$cm_lock_parent" 2>/dev/null || true; fi
		if [ "$cm_lock_root_created" -eq 1 ]; then rmdir "$cm_lock_root" 2>/dev/null || true; fi
	fi
}

comments_check_guards() {
	if [ -n "$1" ] && [ "$1" != "$cm_guard" ]; then
		printf 'error: comments context is stale\n' >&2; return 4
	fi
	if [ -n "$2" ]; then
		_ccg_revision=$(comments_revision "$3") || return 1
		if [ "$2" != "$_ccg_revision" ]; then
			printf 'error: comments document is stale\n' >&2; return 4
		fi
	fi
}

comments_remove_document() {
	comments_safe_path "$1" || return 1
	comments_check_guards "${3:-}" "$2" "$1" || return $?
	rm -f "$1"
}

# All candidates are siblings. Recheck inside the lock immediately before rename
# and retain candidates on any detected conflict (external editors use no lock).
comments_replace() {
	_cr_path=$1 _cr_source=$2 _cr_expected=$3 _cr_guard=${4:-}
	_cr_context=${cm_context:-} _cr_scope=${cm_scope:-active}
	comments_safe_path "$_cr_path" || return 1
	if [ ! -f "$_cr_source" ] || [ -L "$_cr_source" ]; then comments_error 'comments candidate is not a readable regular file'; return 1; fi
	comments_state || return 1
	if [ "$_cr_scope" != active ] && [ -n "$_cr_context" ] && [ -n "$_cr_guard" ]; then comments_select_context "$_cr_context" || return 1; fi
	comments_check_guards "$_cr_guard" "$_cr_expected" "$_cr_path" || return $?
	_cr_candidate=$(mktemp "$_cr_path.candidate.XXXXXX") || { comments_error 'could not create comments candidate'; return 1; }
	if ! cp "$_cr_source" "$_cr_candidate"; then
		comments_error "could not write comments candidate: $_cr_candidate"; return 1
	fi
	comments_state || return 1
	if [ "$_cr_scope" != active ] && [ -n "$_cr_context" ] && [ -n "$_cr_guard" ]; then comments_select_context "$_cr_context" || return 1; fi
	comments_safe_path "$_cr_path" || return 1
	if ! comments_check_guards "$_cr_guard" "$_cr_expected" "$_cr_path" 2>/dev/null; then
		printf 'error: comments document is stale; candidate preserved at %s\n' "$_cr_candidate" >&2; return 4
	fi
	if ! mv "$_cr_candidate" "$_cr_path"; then comments_error "could not replace comments document; candidate preserved at $_cr_candidate"; return 1; fi
}

comments_publish() {
	_cp_context=$1 _cp_source=$2 _cp_guard=${3:-}
	comments_require_token "$_cp_context" || return 1
	_cp_parent=$cm_root/results/$_cp_context
	comments_safe_path "$_cp_parent/current" || return 1
	_cp_previous=$(comments_revision "$_cp_parent/current") || return 1
	mkdir -p "$_cp_parent" || { comments_error 'could not create comments result directory'; return 1; }
	_cp_temporary=$(mktemp -d "$_cp_parent/.generation.XXXXXX") || { comments_error 'could not create comments generation'; return 1; }
	_cp_generation=$(printf '%s\000' "$_cp_temporary" "$$" | git hash-object --stdin)
	_cp_destination=$_cp_parent/$_cp_generation
	comments_safe_path "$_cp_destination" || return 1
	[ ! -e "$_cp_destination" ] || { comments_error 'comments generation already exists'; return 1; }
	_cp_local=absent _cp_shared=absent
	for _cp_document in local shared; do
		if [ -L "$_cp_source/$_cp_document.md" ] || { [ -e "$_cp_source/$_cp_document.md" ] && [ ! -f "$_cp_source/$_cp_document.md" ]; }; then
			comments_error 'unsafe comments generation source'; return 1
		fi
		if [ -f "$_cp_source/$_cp_document.md" ]; then
			if ! cp "$_cp_source/$_cp_document.md" "$_cp_temporary/$_cp_document.md"; then
				comments_error "could not copy comments document: $_cp_document"; return 1
			fi
			case "$_cp_document" in local) _cp_local=present ;; shared) _cp_shared=present ;; esac
		fi
	done
	for _cp_auxiliary in source-baseline.md source-current.md source-previous.md source-conflict delivery; do
		if [ -f "$_cp_source/$_cp_auxiliary" ]; then
			comments_safe_path "$_cp_source/$_cp_auxiliary" || return 1
			cp "$_cp_source/$_cp_auxiliary" "$_cp_temporary/$_cp_auxiliary" || return 1
		fi
	done
	if ! printf 'context\t%s\nlocal\t%s\nshared\t%s\n' "$_cp_context" "$_cp_local" "$_cp_shared" >"$_cp_temporary/manifest.candidate"; then
		comments_error 'could not write comments generation manifest'; return 1
	fi
	# Preserve the publication boundary independently of later edits to the
	# retained files. Undo must not overwrite an older editor's session edits.
	for _cp_document in local shared; do
		_cp_bytes=$(comments_revision "$_cp_temporary/$_cp_document.md") || return 1
		printf '%s_revision\t%s\n' "$_cp_document" "$_cp_bytes" >>"$_cp_temporary/manifest.candidate" || return 1
	done
	if [ -f "$_cp_source/manifest" ]; then
		_cp_session=$(comments_field "$_cp_source/manifest" session) || return 1
		if [ -n "$_cp_session" ]; then
			comments_require_token "$_cp_session" || return 1
			printf 'session\t%s\n' "$_cp_session" >>"$_cp_temporary/manifest.candidate" || return 1
		fi
		for _cp_statefield in kind full_base last_tip; do
			_cp_statevalue=$(comments_field "$_cp_source/manifest" "$_cp_statefield") || return 1
			if [ -n "$_cp_statevalue" ]; then printf '%s\t%s\n' "$_cp_statefield" "$_cp_statevalue" >>"$_cp_temporary/manifest.candidate" || return 1; fi
		done
	fi
	if ! mv "$_cp_temporary/manifest.candidate" "$_cp_temporary/manifest"; then comments_error 'could not publish comments generation manifest'; return 1; fi
	# Recheck the source pair after copying. Any concurrent source edit keeps
	# the old current generation reachable; never publish a mixed pair.
	for _cp_document in local shared; do
		if [ -f "$_cp_temporary/$_cp_document.md" ]; then
			if ! cmp -s "$_cp_source/$_cp_document.md" "$_cp_temporary/$_cp_document.md"; then
				printf 'error: comments document is stale\n' >&2; return 4
			fi
		elif [ -e "$_cp_source/$_cp_document.md" ] || [ -L "$_cp_source/$_cp_document.md" ]; then
			printf 'error: comments document is stale\n' >&2; return 4
		fi
	done
	if ! mv "$_cp_temporary" "$_cp_destination"; then comments_error 'could not publish comments generation'; return 1; fi
	_cp_pointer=$(mktemp "$_cp_parent/current.candidate.XXXXXX") || { comments_error 'could not create comments generation pointer'; return 1; }
	if ! printf '%s\n' "$_cp_generation" >"$_cp_pointer"; then comments_error 'could not write comments generation pointer'; return 1; fi
	if [ -n "$_cp_guard" ]; then
		comments_state || return 1
		comments_check_guards "$_cp_guard" '' '' || return $?
	fi
	comments_safe_path "$_cp_parent/current" || return 1
	_cp_now=$(comments_revision "$_cp_parent/current") || return 1
	if [ "$_cp_now" != "$_cp_previous" ]; then
		printf 'error: comments result is stale; candidate preserved at %s\n' "$_cp_pointer" >&2; return 4
	fi
	if ! mv "$_cp_pointer" "$_cp_parent/current"; then comments_error 'could not publish comments generation pointer'; return 1; fi
}

comments_header() {
	printf '# Comments\n\n<!-- git-review-comments v1\ncontext %s\n-->\n' "$cm_context"
}

comments_select_context() {
	_cselect_requested=$1
	comments_state || return 1
	if [ -n "$_cselect_requested" ]; then
		comments_require_token "$_cselect_requested" || return 1
		if [ "$cm_context" != "$_cselect_requested" ]; then
			cm_context=$_cselect_requested
			comments_load_stored || return 1
		fi
	elif [ -z "$cm_context" ] && [ "$cm_active" -eq 0 ]; then
		_cselect_count=0
		_cselect_contexts=$(comments_stored_contexts) || return 1
		_cselect_contexts=$(printf '%s\n' "$_cselect_contexts" | sort -u)
		while IFS= read -r _cselect_token; do
			[ -n "$_cselect_token" ] || continue
			cm_context=$_cselect_token
			_cselect_count=$((_cselect_count + 1))
		done <<EOF
$_cselect_contexts
EOF
		if [ "$_cselect_count" -gt 1 ]; then comments_error 'select a comments context with --context'; return 1; fi
		if [ "$_cselect_count" -eq 1 ]; then comments_load_stored || return 1; fi
	fi
	[ -n "$cm_context" ] || { comments_error 'comments context not found'; return 1; }
	comments_require_token "$cm_context" || return 1
	if [ -z "$cm_dir" ]; then cm_dir=$(comments_result_dir "$cm_context") || return 1; fi
	[ -n "$cm_dir" ] || { comments_error 'comments context has no retained documents'; return 1; }
}

comments_entries() {
	_ce_path=$cm_dir/$1.md
	_ce_revision=$(comments_revision "$_ce_path") || return 1
	[ "$_ce_revision" != absent ] || { comments_error 'comments document is absent'; return 1; }
	if ! _ce_rows=$(walk_normalize <"$_ce_path" | comments_contours entries); then
		comments_error 'comment boundaries could not be preserved; document unchanged'; return 1
	fi
	porcelain_row comments-document "$_ce_path" "$cm_context" "$1" present "$_ce_revision"
	if [ -n "$_ce_rows" ]; then printf '%s\n' "$_ce_rows"; fi
}

comments_renumber() {
	_cn_path=$cm_dir/$1.md
	_cn_guard=$cm_guard
	_cn_revision=$(comments_revision "$_cn_path") || return 1
	[ "$_cn_revision" != absent ] || { comments_error 'comments document is absent'; return 1; }
	comments_check_guards "$2" "$3" "$_cn_path" || return $?
	_cn_candidate=$(mktemp "$_cn_path.candidate.XXXXXX") || return 1
	_cn_final_lf=0
	if [ -z "$(tail -c 1 "$_cn_path")" ] && [ -s "$_cn_path" ]; then _cn_final_lf=1; fi
	# shellcheck disable=SC2094 # Both views read the original; output is a sibling.
	if ! walk_normalize <"$_cn_path" | comments_contours renumber "$_cn_path" "$_cn_final_lf" >"$_cn_candidate"; then
		rm -f "$_cn_candidate"
		comments_error 'comment boundaries could not be preserved; document unchanged'; return 1
	fi
	if cmp -s "$_cn_candidate" "$_cn_path"; then rm -f "$_cn_candidate"; return 0; fi
	comments_replace "$_cn_path" "$_cn_candidate" "$_cn_revision" "$_cn_guard" || return $?
	rm -f "$_cn_candidate"
}

comments_same_file() {
	if [ -f "$1" ] && [ -f "$2" ]; then cmp -s "$1" "$2"
	elif [ ! -e "$1" ] && [ ! -e "$2" ]; then return 0
	else return 1
	fi
}

# An existing retained document must be copied BEFORE its editable path reaches
# the panel; otherwise manual edits would change the result that abort preserves.
# Every review gets a nonce, including a provisional session without documents.
# Thus a form opened during an earlier identical review cannot write to this one.
comments_begin_session() (
	comments_state || exit 1
	_cb_guard=$cm_guard
	comments_lock "${cm_context:-$cm_guard}" || exit 1
	trap 'comments_unlock' 0
	trap 'exit 1' 1 2 15
	comments_state || exit 1
	comments_check_guards "$_cb_guard" '' '' || exit $?
	if [ "$cm_identity" = resolved ]; then comments_materialize '' 0 ''
	else
		comments_safe_path "$cm_root/sessions" || exit 1
		mkdir -p "$cm_root/sessions" || exit 1
		_cb_allocate=$(mktemp -d "$cm_root/sessions/.new.XXXXXX") || exit 1
		_cb_session=$(printf '%s\000' "$_cb_allocate" "$$" | git hash-object --stdin) || exit 1
		printf 'session\t%s\ncontext\t\nowner_gitdir\t%s\ncustodian\t%s\nkind\t%s\nfull_base\t%s\nlast_tip\t%s\n' \
			"$_cb_session" "$cm_gitdir" "$cm_branch" "$cm_kind" "$cm_full_base" "$cm_tip" >"$_cb_allocate/manifest" || exit 1
		mv "$_cb_allocate" "$cm_root/sessions/$_cb_session" || exit 1
		git config "branch.$cm_branch.reviewcommentssession" "$_cb_session" || exit 1
		git config "branch.$cm_branch.reviewcommentsowner" "$cm_gitdir"
	fi
)

# Separate document baselines from retained results. These copies contain prose
# only; no git object, index, worktree snapshot or code retention is involved.
comments_materialize() {
	_cmat_requested=$1 _cmat_new=$2 _cmat_use=$3
	_cmat_previous=$cm_context
	_cmat_provisional=''
	if [ "$cm_provisional" -eq 1 ]; then _cmat_provisional=$cm_dir; cm_session=''; fi
	if [ -n "$_cmat_requested" ]; then
		if [ -n "$cm_context" ] && [ "$_cmat_requested" != "$cm_context" ]; then
			comments_error 'comments context does not match the current session'; return 1
		fi
		if [ -z "$cm_context" ] && [ ! -f "$cm_root/contexts/$_cmat_requested/manifest" ]; then
			comments_error 'comments context not found'; return 1
		fi
		cm_context=$_cmat_requested
	fi
	if [ -n "$_cmat_use" ]; then
		comments_require_token "$_cmat_use" || return 1
		[ -f "$cm_root/contexts/$_cmat_use/manifest" ] || { comments_error 'comments context not found'; return 1; }
		cm_context=$_cmat_use
	fi
	if [ "$_cmat_new" -eq 1 ]; then cm_context=''; fi
	if [ -n "$cm_session" ] && { [ "$_cmat_new" -eq 1 ] || [ "$cm_context" != "$_cmat_previous" ]; }; then
		for _cmat_doc in local shared; do
			comments_safe_path "$cm_dir/$_cmat_doc.md" || return 1
			if ! comments_same_file "$cm_dir/$_cmat_doc.md" "$cm_dir/baseline/$_cmat_doc.md"; then
				comments_error 'preserve or discard the current comments preparation before changing context'; return 1
			fi
		done
		cm_session=''
	fi
	if [ -n "$cm_session" ]; then return 0; fi
	if [ "$cm_identity" = ambiguous ] && [ "$_cmat_new" -eq 0 ] && [ -z "$_cmat_use" ] && [ -z "$_cmat_requested" ]; then
		comments_error 'choose --new-context or --use-context before writing comments'; return 1
	fi
	comments_safe_path "$cm_root/contexts" || return 1
	comments_safe_path "$cm_root/sessions" || return 1
	mkdir -p "$cm_root/contexts" "$cm_root/sessions" || { comments_error 'could not create comments storage'; return 1; }
	if [ -z "$cm_context" ]; then
		_cmat_allocate=$(mktemp -d "$cm_root/contexts/.new.XXXXXX") || return 1
		cm_context=$(printf '%s\000' "$_cmat_allocate" "$$" | git hash-object --stdin)
		if ! mv "$_cmat_allocate" "$cm_root/contexts/$cm_context"; then comments_error 'could not allocate comments context'; return 1; fi
		if [ "$_cmat_new" -eq 1 ]; then cm_seed=0; fi
	fi
	comments_require_token "$cm_context" || return 1
	_cmat_manifest=$cm_root/contexts/$cm_context/manifest
	comments_safe_path "$_cmat_manifest" || return 1
	if [ -f "$_cmat_manifest" ]; then
		_cmat_owner=$(comments_field "$_cmat_manifest" owner_gitdir) || return 1
		if [ "$_cmat_owner" != "$cm_gitdir" ]; then comments_error 'comments context belongs to another gitdir'; return 1; fi
	else
		mkdir -p "$cm_root/contexts/$cm_context" || return 1
		if ! printf 'context\t%s\nkind\t%s\nsource\t%s\ntarget\t%s\nfull_base\t%s\nlast_tip\t%s\nowner_gitdir\t%s\n' \
			"$cm_context" "$cm_kind" "$cm_source" "$cm_target" "$cm_full_base" "$cm_tip" "$cm_gitdir" >"$_cmat_manifest.candidate"; then return 1; fi
		mv "$_cmat_manifest.candidate" "$_cmat_manifest" || return 1
	fi
	_cmat_allocate=$(mktemp -d "$cm_root/sessions/.new.XXXXXX") || return 1
	cm_session=$(printf '%s\000' "$_cmat_allocate" "$$" | git hash-object --stdin)
	cm_dir=$cm_root/sessions/$cm_session
	comments_safe_path "$cm_dir/manifest" || return 1
	[ ! -e "$cm_dir" ] || { comments_error 'comments session already exists'; return 1; }
	mkdir "$_cmat_allocate/baseline" || return 1
	_cmat_result=$(comments_result_dir "$cm_context") || return 1
	# Source presence is independent of seed selection: inherited Markdown is
	# still the destination baseline, even when it does not seed this context.
	if git cat-file -e "$cm_tip:.review/comments.md" 2>/dev/null; then
		git show "$cm_tip:.review/comments.md" >"$_cmat_allocate/source-baseline.md" || return 1
	fi
	for _cmat_doc in local shared; do
		if [ -n "$_cmat_result" ]; then
			comments_safe_path "$_cmat_result/$_cmat_doc.md" || return 1
			_cmat_copy=$_cmat_result/$_cmat_doc.md
			if [ "$_cmat_doc" = shared ]; then
				comments_safe_path "$_cmat_result/source-baseline.md" || return 1
				if comments_same_file "$_cmat_allocate/source-baseline.md" "$_cmat_result/source-baseline.md" ||
					comments_same_file "$_cmat_allocate/source-baseline.md" "$_cmat_result/shared.md"; then :
				elif comments_same_file "$_cmat_result/shared.md" "$_cmat_result/source-baseline.md"; then
					_cmat_copy=$_cmat_allocate/source-baseline.md
				else
					printf 'Source and retained Shared changed separately.\n' >"$_cmat_allocate/source-conflict" || return 1
					if [ -f "$_cmat_allocate/source-baseline.md" ]; then cp "$_cmat_allocate/source-baseline.md" "$_cmat_allocate/source-current.md" || return 1; fi
					if [ -f "$_cmat_result/source-baseline.md" ]; then cp "$_cmat_result/source-baseline.md" "$_cmat_allocate/source-previous.md" || return 1; fi
				fi
			fi
			if [ -f "$_cmat_copy" ]; then cp "$_cmat_copy" "$_cmat_allocate/$_cmat_doc.md" || return 1; fi
		elif [ "$_cmat_doc" = shared ] && [ "$cm_seed" -eq 1 ]; then
			git show "$cm_tip:.review/comments.md" >"$_cmat_allocate/shared.md" || return 1
		fi
		if [ -f "$_cmat_allocate/$_cmat_doc.md" ]; then cp "$_cmat_allocate/$_cmat_doc.md" "$_cmat_allocate/baseline/$_cmat_doc.md" || return 1; fi
	done
	if ! printf 'session\t%s\ncontext\t%s\nowner_gitdir\t%s\ncustodian\t%s\nkind\t%s\nfull_base\t%s\nlast_tip\t%s\n' \
		"$cm_session" "$cm_context" "$cm_gitdir" "$cm_branch" "$cm_kind" "$cm_full_base" "$cm_tip" >"$_cmat_allocate/manifest"; then return 1; fi
	{
		for _cmat_doc in local shared; do
			_cmat_presence=absent
			if [ -f "$_cmat_allocate/baseline/$_cmat_doc.md" ]; then _cmat_presence=present; fi
			printf '%s\t%s\n' "$_cmat_doc" "$_cmat_presence"
		done
	} >"$_cmat_allocate/baseline/manifest" || return 1
	mv "$_cmat_allocate" "$cm_dir" || return 1
	git config "branch.$cm_branch.reviewcommentscontext" "$cm_context" || return 1
	git config "branch.$cm_branch.reviewcommentssession" "$cm_session" || return 1
	git config "branch.$cm_branch.reviewcommentsowner" "$cm_gitdir" || return 1
	if [ -n "$_cmat_provisional" ]; then
		comments_safe_path "$_cmat_provisional/manifest" || return 1
		rm -f "$_cmat_provisional/manifest"
		rmdir "$_cmat_provisional" || return 1
	fi
	cm_provisional=0
}

# Path codec transports bytes exactly once; it is not URI decoding or path
# normalization. The wire format cannot carry literal TAB/CR/LF path bytes.
comments_encode_path() {
	# A final sentinel keeps a trailing LF distinguishable from EOF in awk.
	printf '%sX' "$1" | awk '{lines[NR]=$0} END {
		for(i=1;i<=NR;i++) {
			line=lines[i]; if(i==NR) line=substr(line,1,length(line)-1)
			gsub(/%/,"%25",line);gsub(/\t/,"%09",line);gsub(/\r/,"%0D",line);gsub(/>/,"%3E",line)
			if(i>1) printf "%%0A"; printf "%s",line
		}
	}'
}

# Compare decimal coordinates as strings: shell integers and awk floats cannot
# represent every value accepted by a decimal wire field. Leading zeroes are OK.
comments_positive_le() {
	awk -v first="$1" -v last="$2" 'BEGIN {
		sub(/^0+/,"",first); sub(/^0+/,"",last)
		if(first=="" || last=="") exit 1
		if(length(first)<length(last)) exit 0
		if(length(first)>length(last)) exit 1
		exit !("x" first <= "x" last)
	}'
}

# shellcheck disable=SC2154 # Options are assigned by the comments dispatcher.
comments_capture_location() {
	if [ "${_cm_phase:-}" = conflict ] && [ -n "$path$base_path$head_path$side$start_line$end_line" ]; then
		comments_error 'only general comments can be captured during a finish conflict'; return 1
	fi
	cm_loc_base=$base cm_loc_head=$head
	cm_loc_base_path=$base_path cm_loc_head_path=$head_path
	cm_loc_side=$side cm_loc_start=$start_line cm_loc_end=$end_line
	cm_loc_unversioned=$unversioned
	if { [ -n "$base" ] && [ -z "$head" ]; } || { [ -z "$base" ] && [ -n "$head" ]; }; then comments_error '--base and --head must be provided together'; return 1; fi
	if { [ -n "$start_line" ] && [ -z "$end_line" ]; } || { [ -z "$start_line" ] && [ -n "$end_line" ]; }; then comments_error 'start and end lines must be provided together'; return 1; fi
	if [ -n "$cm_loc_side" ]; then
		case "$cm_loc_side" in base|head) ;; *) comments_error 'comment side must be base or head'; return 1 ;; esac
	fi
	if [ -n "$start_line" ]; then
		case "$start_line:$end_line" in *[!0-9:]*|:*|*:) comments_error 'comment lines must be positive integers'; return 1 ;; esac
		if ! comments_positive_le "$start_line" "$end_line" || [ -z "$cm_loc_side" ]; then comments_error 'comment range must be positive, ordered and have a side'; return 1; fi
	fi
	if [ -z "$base" ]; then cm_loc_base=$cm_capture_base cm_loc_head=$cm_capture_head; fi
	if [ -n "$cm_loc_base" ] && [ -n "$cm_loc_head" ]; then
		for _ccl_object in "$cm_loc_base" "$cm_loc_head"; do
			comments_token_valid "$_ccl_object" || { comments_error 'comment references must be full object IDs'; return 1; }
			_ccl_type=$(git cat-file -t "$_ccl_object" 2>/dev/null || true)
			case "$_ccl_type" in commit|tree) ;; *) comments_error 'comment reference is not an available commit or tree'; return 1 ;; esac
		done
	fi
	for _ccl_path in "$path" "$base_path" "$head_path"; do
		[ -n "$_ccl_path" ] || continue
		case "$_ccl_path/" in /*|*'/../'*|../*|*'/./'*|./*|*'//'*) comments_error 'comment path must be relative to the repository root'; return 1 ;; esac
		case "$_ccl_path" in *"$(printf '\t')"*|*"$(printf '\r')"*|*'
'*) comments_error 'comment path cannot be represented in porcelain'; return 1 ;; esac
	done
	if [ -n "$path" ]; then
		if [ -z "$cm_loc_base" ] || [ -z "$cm_loc_head" ]; then comments_error 'code location has no resolved capture range'; return 1; fi
		# Route Git/text comparisons through the established normalization doors.
		_ccl_name=$(printf '%s\n' "$path" | walk_normalize)
		_ccl_rename=$(COMMENTS_LOCATION_PATH="$_ccl_name" changed_paths "$cm_loc_base" "$cm_loc_head" --name-status | COMMENTS_LOCATION_PATH="$_ccl_name" awk -F '\t' '$1 ~ /^R/ && ($2==ENVIRON["COMMENTS_LOCATION_PATH"] || $3==ENVIRON["COMMENTS_LOCATION_PATH"]) {print $2;print $3}')
		if [ -n "$_ccl_rename" ]; then
			cm_loc_base_path=$(printf '%s\n' "$_ccl_rename" | sed -n 1p)
			cm_loc_head_path=$(printf '%s\n' "$_ccl_rename" | sed -n 2p)
		else
			if git cat-file -e "$cm_loc_base:$path" 2>/dev/null; then cm_loc_base_path=$path; fi
			if git cat-file -e "$cm_loc_head:$path" 2>/dev/null; then cm_loc_head_path=$path; fi
			if [ "$cm_loc_unversioned" -eq 1 ] && [ -z "$cm_loc_head_path" ]; then cm_loc_head_path=$path; fi
		fi
		if [ -z "$cm_loc_base_path$cm_loc_head_path" ]; then
			comments_error 'comment path is absent from the captured range; use --unversioned for a working file'; return 1
		fi
	fi
	# A changed buffer/working file is never attributed to a historical blob.
	if [ -n "$cm_loc_side" ]; then
		_ccl_selected=$cm_loc_head_path
		if [ "$cm_loc_side" = base ]; then _ccl_selected=$cm_loc_base_path; fi
		[ -n "$_ccl_selected" ] || { comments_error 'comment side requires a path on the selected side'; return 1; }
	fi
	if [ -z "$base" ] && [ -n "$cm_loc_head_path" ] && [ "$cm_loc_side" != base ]; then
		_ccl_root=$(git rev-parse --show-toplevel)
		_ccl_blob=$(git rev-parse --verify "$cm_loc_head:$cm_loc_head_path" 2>/dev/null || true)
		_ccl_work=$(git hash-object --no-filters -- "$_ccl_root/$cm_loc_head_path" 2>/dev/null || true)
		if [ "$_ccl_blob" != "$_ccl_work" ]; then cm_loc_unversioned=1; fi
	fi
	if [ -n "$cm_loc_start" ]; then
		case "$cm_loc_side" in base) _ccl_selected=$cm_loc_base_path; _ccl_ref=$cm_loc_base ;; head) _ccl_selected=$cm_loc_head_path; _ccl_ref=$cm_loc_head ;; esac
		[ -n "$_ccl_selected" ] || { comments_error 'comment lines require a path on the selected side'; return 1; }
		if [ "$cm_loc_unversioned" -eq 0 ]; then
			_ccl_lines=$(git cat-file blob "$_ccl_ref:$_ccl_selected" | awk 'END {print NR}') || return 1
			comments_positive_le "$cm_loc_end" "$_ccl_lines" || { comments_error 'comment line range exceeds the captured blob'; return 1; }
		fi
	fi
}

comments_append() {
	_ca_path=$1 _ca_body=$2 _ca_revision=$3 _ca_guard=$4
	_ca_count=0
	if [ -f "$_ca_path" ]; then
		if ! _ca_count=$(walk_normalize <"$_ca_path" | comments_contours append); then
			comments_error 'close the open code fence or HTML comment before adding a comment'; return 1
		fi
	fi
	_ca_candidate=$(mktemp "$_ca_path.candidate.XXXXXX") || return 1
	if [ -f "$_ca_path" ]; then cat "$_ca_path" >"$_ca_candidate" || return 1
	else comments_header >"$_ca_candidate" || return 1
	fi
	_ca_title=General
	if [ -n "$cm_loc_head_path" ]; then _ca_title=$cm_loc_head_path
	elif [ -n "$cm_loc_base_path" ]; then _ca_title=$cm_loc_base_path
	fi
	_ca_separator=1
	if [ -n "$(tail -c 1 "$_ca_candidate")" ]; then _ca_separator=2; fi
	{
		if [ "$_ca_separator" -eq 2 ]; then printf '\n\n'; else printf '\n'; fi
		printf '## %s. %s\n' "$((_ca_count + 1))" "$_ca_title"
		if [ -n "$cm_loc_base" ] || [ -n "$cm_loc_head_path" ] || [ -n "$cm_loc_base_path" ]; then
			printf '\n<!-- git-review-comment v1\n'
			if [ -n "$cm_loc_base" ] && [ -n "$cm_loc_head" ]; then printf 'base %s\nhead %s\n' "$cm_loc_base" "$cm_loc_head"; fi
			if [ -n "$cm_loc_base_path" ]; then printf 'base-path %s\n' "$(comments_encode_path "$cm_loc_base_path")"; fi
			if [ -n "$cm_loc_head_path" ]; then printf 'head-path %s\n' "$(comments_encode_path "$cm_loc_head_path")"; fi
			if [ -n "$cm_loc_side" ]; then printf 'side %s\n' "$cm_loc_side"; fi
			if [ -n "$cm_loc_start" ]; then printf 'start %s\nend %s\n' "$cm_loc_start" "$cm_loc_end"; fi
			if [ "$cm_loc_unversioned" -eq 1 ]; then printf 'unversioned 1\n'; fi
			printf -- '-->\n'
		fi
		printf '\n'
		cat "$_ca_body"
		# Preserve stdin bodies including their final LF, add one only if absent.
		if [ -n "$(tail -c 1 "$_ca_body")" ]; then printf '\n'; fi
	} >>"$_ca_candidate" || return 1
	_ca_new_count=$(comments_scan "$_ca_candidate") || return 1
	[ "$_ca_new_count" -eq "$((_ca_count + 1))" ] || { comments_error 'comment would create ambiguous entry boundaries'; return 1; }
	comments_replace "$_ca_path" "$_ca_candidate" "$_ca_revision" "$_ca_guard" || return $?
	rm -f "$_ca_candidate"
}

comments_decode_path() {
	COMMENTS_ENCODED_PATH=$1 awk 'BEGIN {
		s=ENVIRON["COMMENTS_ENCODED_PATH"]
		for(i=1;i<=length(s);i++) {
			c=substr(s,i,1)
			if(c!="%") {printf "%s",c;continue}
			escape=substr(s,i,3); i+=2
			if(escape=="%25") printf "%%"
			else if(escape=="%09") printf "\t"
			else if(escape=="%0D") printf "\r"
			else if(escape=="%0A") printf "\n"
			else if(escape=="%3E") printf ">"
			else exit 1
		}
	}'
}

comments_diff() {
	_cd_document=$1 _cd_entry=$2 _cd_porcelain=$3
	case "$_cd_entry" in ''|*[!0-9]*) comments_error '--entry requires a positive physical ordinal'; return 1 ;; esac
	comments_positive_le "$_cd_entry" "$_cd_entry" || { comments_error '--entry requires a positive physical ordinal'; return 1; }
	_cd_path=$cm_dir/$_cd_document.md
	comments_check_guards "$4" "$5" "$_cd_path" || return $?
	_cd_rows=$(comments_entries "$_cd_document") || return 1
	_cd_selected=$(printf '%s\n' "$_cd_rows" | awk -F '\t' -v ordinal="$_cd_entry" '$2==ordinal && $1!="comments-document" {print}')
	if ! printf '%s\n' "$_cd_selected" | grep -q '^comment-entry'; then comments_error 'comment entry not found'; return 1; fi
	_cd_version=$(printf '%s\n' "$_cd_selected" | awk -F '\t' '$1=="comment-version" {print $3 " " $4}')
	if [ -z "$_cd_version" ]; then printf 'error: comment has no reproducible historical range\n' >&2; return 5; fi
	_cd_base=${_cd_version% *} _cd_head=${_cd_version#* }
	_cd_base_tree=$(git rev-parse --verify "$_cd_base^{tree}" 2>/dev/null || true)
	_cd_head_tree=$(git rev-parse --verify "$_cd_head^{tree}" 2>/dev/null || true)
	if [ -z "$_cd_base_tree" ] || [ -z "$_cd_head_tree" ]; then printf 'error: historical revision or content not found\n' >&2; return 5; fi
	_cd_base_path='' _cd_head_path='' _cd_base_blob='' _cd_head_blob=''
	for _cd_side in base head; do
		_cd_encoded=$(printf '%s\n' "$_cd_selected" | awk -F '\t' -v side="$_cd_side" '$1=="comment-path" && $3==side {print $4}')
		[ -n "$_cd_encoded" ] || continue
		_cd_decoded=$(if comments_decode_path "$_cd_encoded"; then printf x; else exit 1; fi) || { comments_error 'comment path encoding is invalid'; return 1; }
		_cd_decoded=${_cd_decoded%x}
		case "$_cd_decoded" in *"$(printf '\t')"*|*"$(printf '\r')"*|*'
'*) comments_error 'comment path cannot be represented in porcelain'; return 1 ;; esac
		case "$_cd_side" in base) _cd_tree=$_cd_base_tree ;; head) _cd_tree=$_cd_head_tree ;; esac
		_cd_blob=$(git rev-parse --verify "$_cd_tree:$_cd_decoded" 2>/dev/null || true)
		if [ -z "$_cd_blob" ] || [ "$(git cat-file -t "$_cd_blob" 2>/dev/null || true)" != blob ]; then printf 'error: historical revision or content not found\n' >&2; return 5; fi
		case "$_cd_side" in base) _cd_base_path=$_cd_decoded; _cd_base_blob=$_cd_blob ;; head) _cd_head_path=$_cd_decoded; _cd_head_blob=$_cd_blob ;; esac
	done
	if printf '%s\n' "$_cd_selected" | grep -q '^comment-unversioned'; then
		printf 'note: the captured location was unversioned; this range shows only the recorded Git objects\n' >&2
	fi
	set --
	if [ -n "$_cd_base_path" ]; then set -- "$@" ":(top,literal)$_cd_base_path"; fi
	if [ -n "$_cd_head_path" ] && [ "$_cd_head_path" != "$_cd_base_path" ]; then set -- "$@" ":(top,literal)$_cd_head_path"; fi
	# A general entry needs the changed blobs too, not merely both root tree
	# objects. Stage human output so missing content cannot leak a partial diff.
	if [ "$_cd_porcelain" -eq 0 ]; then
		if ! _cd_rendered=$(git --no-pager diff --no-ext-diff --no-textconv "$_cd_base_tree" "$_cd_head_tree" -- "$@" 2>/dev/null); then
			printf 'error: historical revision or content not found\n' >&2; return 5
		fi
	elif [ -z "$_cd_base_path$_cd_head_path" ]; then
		if ! git --no-pager diff --no-ext-diff --no-textconv "$_cd_base_tree" "$_cd_head_tree" -- >/dev/null 2>&1; then
			printf 'error: historical revision or content not found\n' >&2; return 5
		fi
	fi
	if [ "$_cd_porcelain" -eq 1 ]; then
		porcelain_row comment-diff "$_cd_entry" "$_cd_base_tree" "$_cd_head_tree"
		if [ -n "$_cd_base_path$_cd_head_path" ]; then
			if [ -n "$_cd_base_path" ]; then porcelain_row comment-blob "$(comments_encode_path "$_cd_base_path")" base present "$_cd_base_blob"
			else porcelain_row comment-blob "$(comments_encode_path "$_cd_head_path")" base absent
			fi
			if [ -n "$_cd_head_path" ]; then porcelain_row comment-blob "$(comments_encode_path "$_cd_head_path")" head present "$_cd_head_blob"
			else porcelain_row comment-blob "$(comments_encode_path "$_cd_base_path")" head absent
			fi
		fi
		printf '%s\n' "$_cd_selected" | awk -F '\t' '$1=="comment-location" {print}'
	else
		if [ -n "$_cd_rendered" ]; then printf '%s\n' "$_cd_rendered"; fi
	fi
}

# Custody checks do not parse Markdown: broken prose never blocks code
# navigation. They validate storage and its owner before a code verb can move
# branches or remove the config that identifies a session.
comments_check_orphan_claim() {
	comments_safe_path "$cm_root/sessions" || return 1
	for _cco_manifest in "$cm_root"/sessions/*/manifest; do
		[ -e "$_cco_manifest" ] || [ -L "$_cco_manifest" ] || continue
		_cco_dir=${_cco_manifest%/manifest}
		_cco_token=${_cco_dir##*/}
		# Incomplete mktemp candidates are recovery data, never custodians.
		comments_token_valid "$_cco_token" || continue
		_cco_owner=$(comments_field "$_cco_manifest" owner_gitdir) || return 1
		_cco_branch=$(comments_field "$_cco_manifest" custodian) || return 1
		if [ "$_cco_owner" != "$cm_gitdir" ] || [ "$_cco_branch" != "$1" ]; then continue; fi
		_cco_context=$(comments_field "$_cco_manifest" context) || return 1
		if [ -n "$_cco_context" ] || [ -e "$_cco_dir/local.md" ] || [ -L "$_cco_dir/local.md" ] ||
			[ -e "$_cco_dir/shared.md" ] || [ -L "$_cco_dir/shared.md" ]; then
			comments_error 'comments session ownership metadata is incomplete'; return 1
		fi
	done
}

comments_preflight_branch() {
	_cc_branch=$1
	cm_gitdir=$(git rev-parse --absolute-git-dir) || return 1
	cm_root=$cm_gitdir/review-comments
	cc_session=$(git config "branch.$_cc_branch.reviewcommentssession" || true)
	cc_context=$(git config "branch.$_cc_branch.reviewcommentscontext" || true)
	cc_owner=$(git config "branch.$_cc_branch.reviewcommentsowner" || true)
	cc_dir=''
	if [ -z "$cc_session$cc_context$cc_owner" ]; then comments_check_orphan_claim "$_cc_branch"; return $?; fi
	if [ "$cc_owner" != "$cm_gitdir" ]; then comments_error 'comments session belongs to another gitdir'; return 1; fi
	comments_require_token "$cc_session" || return 1
	if [ -n "$cc_context" ]; then comments_require_token "$cc_context" || return 1; fi
	if [ -n "$cc_context" ] && [ "$(comments_field "$cm_root/contexts/$cc_context/manifest" owner_gitdir)" != "$cm_gitdir" ]; then
		comments_error 'comments context belongs to another gitdir'; return 1
	fi
	cc_dir=$cm_root/sessions/$cc_session
	comments_safe_path "$cc_dir/manifest" || return 1
	if [ "$(comments_field "$cc_dir/manifest" session)" != "$cc_session" ] ||
		[ "$(comments_field "$cc_dir/manifest" context)" != "$cc_context" ] ||
		[ "$(comments_field "$cc_dir/manifest" owner_gitdir)" != "$cm_gitdir" ] ||
		[ "$(comments_field "$cc_dir/manifest" custodian)" != "$_cc_branch" ]; then
		comments_error 'comments session ownership does not match'; return 1
	fi
	comments_safe_path "$cc_dir/local.md" || return 1
	comments_safe_path "$cc_dir/shared.md" || return 1
}

comments_lock_branch() {
	comments_preflight_branch "$1" || return 1
	[ -n "$cc_session" ] || return 0
	comments_lock "${cc_context:-$cc_session}" || return 1
	comments_preflight_branch "$1"
}

comments_transfer_preflight() {
	comments_preflight_branch "$1" || return 1
	[ -n "$cc_session" ] || return 0
	_ct_target=$2
	_ct_existing=$(git config "branch.$_ct_target.reviewcommentssession" || true)
	_ct_owner=$(git config "branch.$_ct_target.reviewcommentsowner" || true)
	_ct_context=$(git config "branch.$_ct_target.reviewcommentscontext" || true)
	if [ -n "$_ct_existing$_ct_owner$_ct_context" ] &&
		{ [ "$_ct_existing" != "$cc_session" ] || [ "$_ct_owner" != "$cc_owner" ] || [ "$_ct_context" != "$cc_context" ]; }; then
		comments_error 'another comments session owns the destination'; return 1
	fi
}

comments_transfer() {
	comments_transfer_preflight "$1" "$2" || return 1
	[ -n "$cc_session" ] || return 0
	_ct_candidate=$(mktemp "$cc_dir/manifest.candidate.XXXXXX") || return 1
	_ct_original_revision=$(comments_revision "$cc_dir/manifest") || return 1
	COMMENTS_CUSTODIAN=$_ct_target awk -F '\t' 'BEGIN {OFS="\t"} $1=="custodian" {$0="custodian\t" ENVIRON["COMMENTS_CUSTODIAN"]} {print}' "$cc_dir/manifest" >"$_ct_candidate" || return 1
	comments_replace "$cc_dir/manifest" "$_ct_candidate" "$_ct_original_revision" || return $?
	rm -f "$_ct_candidate"
	if [ -n "$cc_context" ]; then git config "branch.$_ct_target.reviewcommentscontext" "$cc_context" || return 1
	else git config --unset "branch.$_ct_target.reviewcommentscontext" || true
	fi
	git config "branch.$_ct_target.reviewcommentssession" "$cc_session" || return 1
	git config "branch.$_ct_target.reviewcommentsowner" "$cc_owner"
}

comments_discard_branch() {
	comments_preflight_branch "$1" || return 1
	[ -n "$cc_session" ] || return 0
	# The only recursively removed path is the validated, owned session token;
	# retained generations and other sessions are deliberately outside it.
	comments_safe_path "$cc_dir" || return 1
	rm -rf "$cc_dir"
}

comments_save_compare() {
	comments_state || return 1
	if [ "$cm_active" -ne 1 ] || [ "$cm_kind" != compare ]; then printf 'error: saving comments requires an active compare\n' >&2; return 2; fi
	if [ -z "$cm_session" ] || [ "$cm_provisional" -ne 0 ]; then comments_error 'there are no comments to save'; return 1; fi
	_csc_context=$cm_context
	comments_check_guards "$1" "$2" "$cm_dir/local.md" || return $?
	comments_check_guards "$1" "$3" "$cm_dir/shared.md" || return $?
	comments_lock "$cm_context" || return 1
	comments_state || return 1
	comments_check_guards "$1" "$2" "$cm_dir/local.md" || return $?
	comments_check_guards "$1" "$3" "$cm_dir/shared.md" || return $?
	comments_publish "$_csc_context" "$cm_dir" "$cm_guard" || return $?
	# The result's current pointer IS the discard checkpoint. A second pointer
	# could fail after publication and report failure after advancing the limit.
	# Abort drops only this session; the complete published pair stays reachable.
	printf 'Comments saved.\n'
}

comments_delivery_state() {
	_cds_dir=$1 _cds_state=$2
	_cds_revision=$(comments_revision "$_cds_dir/delivery") || return 1
	_cds_temp=$(mktemp "$_cds_dir/delivery.candidate.XXXXXX") || return 1
	printf 'state\t%s\nbranch\t%s\nsource_branch\t%s\nroot\t%s\n' \
		"$_cds_state" "$cm_delivery_branch" "$cm_delivery_source" "$cm_delivery_root" >"$_cds_temp" || return 1
	comments_replace "$_cds_dir/delivery" "$_cds_temp" "$_cds_revision" || return $?
	rm -f "$_cds_temp"
}

comments_delivery_load() {
	_cdl_dir=$1
	comments_safe_path "$_cdl_dir/delivery" || return 1
	[ -f "$_cdl_dir/delivery" ] || { printf 'error: there is no pending Shared delivery for this context\n' >&2; return 2; }
	cm_delivery_branch=$(comments_field "$_cdl_dir/delivery" branch) || return 1
	cm_delivery_source=$(comments_field "$_cdl_dir/delivery" source_branch) || return 1
	cm_delivery_root=$(comments_field "$_cdl_dir/delivery" root) || return 1
	if [ "$cm_delivery_root" != "$(git rev-parse --show-toplevel)" ] ||
		{ [ "${2:-0}" -eq 0 ] && [ "$cm_delivery_branch" != "$(git symbolic-ref --quiet --short HEAD || true)" ]; }; then
		comments_error 'Shared delivery belongs to another branch or destination'; return 1
	fi
	if git show-ref --verify --quiet "refs/heads/$cm_delivery_source"; then
		comments_preflight_branch "$cm_delivery_source" || return 1
		_cdl_session=$(comments_field "$_cdl_dir/manifest" session) || return 1
		_cdl_context=$(comments_field "$_cdl_dir/manifest" context) || return 1
		if [ "$cc_session" != "$_cdl_session" ] || [ "$cc_context" != "$_cdl_context" ]; then
			comments_error 'Shared delivery source custody changed'; return 1
		fi
	fi
	cm_delivery_path=$cm_delivery_root/.review/comments.md
	if [ -L "$cm_delivery_root/.review" ] || [ -L "$cm_delivery_path" ] ||
		{ [ -e "$cm_delivery_root/.review" ] && [ ! -d "$cm_delivery_root/.review" ]; } ||
		{ [ -e "$cm_delivery_path" ] && [ ! -f "$cm_delivery_path" ]; }; then
		comments_error 'Shared delivery destination is not a safe regular file'; return 1
	fi
}

# Delivery has exactly one allowed destination outside the private store. The
# fixed root is recorded after code extraction and checked on every retry.
comments_delivery_apply() {
	_cda_dir=$1
	comments_delivery_load "$_cda_dir" || return $?
	comments_revision "$_cda_dir/shared.md" >/dev/null || return 1
	comments_revision "$_cda_dir/source-baseline.md" >/dev/null || return 1
	[ -f "$_cda_dir/shared.md" ] || { comments_error 'prepared Shared comments are absent'; return 1; }
	if comments_same_file "$_cda_dir/shared.md" "$cm_delivery_path"; then
		comments_delivery_state "$_cda_dir" delivered || return 1
		comments_safe_path "$_cda_dir/source-conflict" || return 1
		rm -f "$_cda_dir/source-conflict" || return 1
		return 0
	fi
	if [ -f "$_cda_dir/source-conflict" ]; then
		comments_delivery_state "$_cda_dir" pending || return 1
		comments_error 'source and retained Shared changed separately; compare and resolve both versions before delivery'; return 1
	fi
	if ! comments_same_file "$_cda_dir/source-baseline.md" "$cm_delivery_path"; then
		comments_delivery_state "$_cda_dir" pending || return 1
		comments_error 'Shared destination changed; prepared comments and destination were preserved'; return 1
	fi
	_cda_revision=absent
	if [ -f "$cm_delivery_path" ]; then _cda_revision=$(git hash-object --no-filters -- "$cm_delivery_path") || return 1; fi
	mkdir -p "$cm_delivery_root/.review" || return 1
	_cda_temp=$(mktemp "$cm_delivery_path.candidate.XXXXXX") || return 1
	if ! cp "$_cda_dir/shared.md" "$_cda_temp"; then comments_error "could not write Shared candidate: $_cda_temp"; return 1; fi
	comments_delivery_load "$_cda_dir" || return 1
	_cda_now=absent
	if [ -f "$cm_delivery_path" ]; then _cda_now=$(git hash-object --no-filters -- "$cm_delivery_path") || return 1; fi
	if [ "$_cda_revision" != "$_cda_now" ]; then comments_error "Shared destination changed; candidate preserved at $_cda_temp"; return 1; fi
	if ! mv "$_cda_temp" "$cm_delivery_path"; then comments_error "could not prepare Shared comments; candidate preserved at $_cda_temp"; return 1; fi
	comments_delivery_state "$_cda_dir" delivered
}

comments_finish_complete() {
	_cfc_review=$1 _cfc_output=$2
	comments_preflight_branch "$_cfc_review" || return 1
	if [ -z "$cc_session" ] || [ -z "$cc_context" ]; then return 0; fi
	cm_context=$cc_context cm_dir=$cc_dir
	_cfc_failed=0 _cfc_publish_failed=0
	cm_delivery_branch=$_cfc_output cm_delivery_source=$_cfc_review
	cm_delivery_root=$(git rev-parse --show-toplevel)
	if [ ! -f "$cc_dir/shared.md" ] || comments_same_file "$cc_dir/shared.md" "$cc_dir/source-baseline.md"; then
		comments_delivery_state "$cc_dir" unchanged || return 1
	else
		comments_delivery_state "$cc_dir" pending || return 1
		comments_delivery_apply "$cc_dir" || _cfc_failed=1
	fi
	comments_publish "$cc_context" "$cc_dir" || _cfc_publish_failed=1
	if [ "$_cfc_failed" -ne 0 ]; then
		comments_error 'code was extracted but Shared comments could not be prepared; the comments remain recoverable'; return 1
	fi
	if [ "$_cfc_publish_failed" -ne 0 ]; then
		comments_error 'code was extracted but comments results could not be retained; the preparation remains recoverable'; return 1
	fi
}

comments_prepare() {
	_cprep_context=$1 _cprep_check=$2 _cprep_porcelain=$3
	comments_select_context "$_cprep_context" || return 1
	_cprep_dir=$cm_dir
	comments_delivery_load "$cm_dir" || return $?
	_cprep_state=$(comments_field "$cm_dir/delivery" state) || return 1
	case "$_cprep_state" in
		pending|delivered) ;;
		*) printf 'error: there is no pending Shared delivery for this context\n' >&2; return 2 ;;
	esac
	comments_safe_path "$cm_dir/source-baseline.md" || return 1
	comments_safe_path "$cm_dir/shared.md" || return 1
	comments_check_guards "$4" "$5" "$cm_dir/shared.md" || return $?
	if [ "$_cprep_check" -eq 1 ]; then
		# Validate every role before emitting a stream a native comparison could
		# consume. Unsafe/unreadable private data is not an absent baseline.
		_cprep_baseline=$(comments_revision "$cm_dir/source-baseline.md") || return 1
		_cprep_prepared=$(comments_revision "$cm_dir/shared.md") || return 1
		_cprep_destination=absent
		if [ -f "$cm_delivery_path" ]; then _cprep_destination=$(git hash-object --no-filters -- "$cm_delivery_path") || return 1; fi
		if [ "$_cprep_porcelain" -eq 1 ]; then porcelain_row comments-delivery "$cm_context" "$_cprep_state" 'Shared comments delivery.'; fi
		for _cprep_role in baseline prepared destination; do
			case "$_cprep_role" in
				baseline) _cprep_path=$cm_dir/source-baseline.md; _cprep_revision=$_cprep_baseline ;;
				prepared) _cprep_path=$cm_dir/shared.md; _cprep_revision=$_cprep_prepared ;;
				destination) _cprep_path=$cm_delivery_path; _cprep_revision=$_cprep_destination ;;
			esac
			_cprep_presence=present
			if [ "$_cprep_revision" = absent ]; then _cprep_presence=absent; fi
			if [ "$_cprep_porcelain" -eq 1 ]; then porcelain_row comments-delivery-file "$_cprep_path" "$_cprep_role" "$_cprep_presence" "$_cprep_revision"
			else printf '%s: %s (%s)\n' "$_cprep_role" "$_cprep_path" "$_cprep_presence"
			fi
		done
		if [ "$_cprep_porcelain" -eq 0 ]; then
			_cprep_left=$cm_dir/shared.md _cprep_right=$cm_delivery_path
			if [ ! -f "$_cprep_left" ]; then _cprep_left=/dev/null; fi
			if [ ! -f "$_cprep_right" ]; then _cprep_right=/dev/null; fi
			_cprep_diff_status=0
			git --no-pager diff --no-index --no-ext-diff --no-textconv -- "$_cprep_left" "$_cprep_right" || _cprep_diff_status=$?
			if [ "$_cprep_diff_status" -gt 1 ]; then return 1; fi
		fi
		return 0
	fi
	comments_lock "$cm_context" || return 1
	comments_select_context "$_cprep_context" || return 1
	comments_check_guards "$4" "$5" "$cm_dir/shared.md" || return $?
	_cprep_dir=$cm_dir
	comments_delivery_apply "$cm_dir" || return $?
	case "$_cprep_dir" in
		"$cm_root/sessions/"*) comments_publish "$_cprep_context" "$_cprep_dir" || return $? ;;
	esac
	# Update only the delivered path in the original exit snapshot. Reading the
	# whole worktree here would absorb code edited after the partial finish.
	_cprep_oldtree=$(git config "branch.$cm_delivery_source.reviewundoouttree" || true)
	if [ -n "$_cprep_oldtree" ]; then
		_cprep_index=$(mktemp "$cm_gitdir/comments-undo-index.XXXXXX") || return 1
		rm -f "$_cprep_index"
		_cprep_blob=$(git hash-object -w --no-filters -- "$cm_delivery_path") || return 1
		GIT_INDEX_FILE=$_cprep_index git read-tree "$_cprep_oldtree" || return 1
		GIT_INDEX_FILE=$_cprep_index git update-index --add --cacheinfo "100644,$_cprep_blob,.review/comments.md" || return 1
		_cprep_newtree=$(GIT_INDEX_FILE=$_cprep_index git write-tree) || return 1
		rm -f "$_cprep_index"
		git config "branch.$cm_delivery_source.reviewundoouttree" "$_cprep_newtree" || return 1
	fi
	printf 'Shared comments prepared.\n'
}

comments_finish_undo() {
	comments_preflight_branch "$1" || return 1
	if [ -z "$cc_session" ] || [ -z "$cc_context" ]; then return 0; fi
	_cfu_result=$(comments_result_dir "$cc_context") || return 1
	_cfu_delivered_revision=$(comments_revision "$cc_dir/shared.md") || return 1
	if [ -n "$_cfu_result" ] && [ "$(comments_field "$_cfu_result/manifest" session)" = "$cc_session" ]; then
		# Preflight both documents before changing either. A stale editor may
		# still own the original session path after the retained result opens.
		for _cfu_doc in local shared; do
			_cfu_revision=$(comments_revision "$_cfu_result/$_cfu_doc.md") || return 1
			_cfu_destination=$(comments_revision "$cc_dir/$_cfu_doc.md") || return 1
			_cfu_boundary=$(comments_field "$_cfu_result/manifest" "${_cfu_doc}_revision") || return 1
			if [ -z "$_cfu_boundary" ] && [ "$_cfu_revision" != "$_cfu_destination" ]; then
				comments_error 'comments finish baseline is missing; preserve both versions before undoing it'; return 1
			fi
			if [ -n "$_cfu_boundary" ] && [ "$_cfu_destination" != "$_cfu_boundary" ] && [ "$_cfu_destination" != "$_cfu_revision" ]; then
				comments_error 'comments preparation changed after finish; preserve both versions before undoing it'; return 1
			fi
			if [ "$_cfu_doc" = local ]; then _cfu_local_revision=$_cfu_revision; _cfu_local_destination=$_cfu_destination
			else _cfu_shared_revision=$_cfu_revision; _cfu_shared_destination=$_cfu_destination
			fi
		done
		for _cfu_doc in local shared; do
			if [ "$_cfu_doc" = local ]; then _cfu_revision=$_cfu_local_revision; _cfu_destination=$_cfu_local_destination
			else _cfu_revision=$_cfu_shared_revision; _cfu_destination=$_cfu_shared_destination
			fi
			if [ "$_cfu_revision" != absent ]; then
				_cfu_tmp=$(mktemp "$cc_dir/$_cfu_doc.md.candidate.XXXXXX") || return 1
				cp "$_cfu_result/$_cfu_doc.md" "$_cfu_tmp" || return 1
			fi
			_cfu_current=$(comments_revision "$_cfu_result/$_cfu_doc.md") || return 1
			if [ "$_cfu_current" != "$_cfu_revision" ]; then printf 'error: comments document is stale\n' >&2; return 4; fi
			if [ "$_cfu_revision" = absent ]; then
				comments_remove_document "$cc_dir/$_cfu_doc.md" "$_cfu_destination" || return $?
			else
				comments_replace "$cc_dir/$_cfu_doc.md" "$_cfu_tmp" "$_cfu_destination" || return $?
				rm -f "$_cfu_tmp"
			fi
		done
		comments_safe_path "$_cfu_result/source-conflict" || return 1
		if [ ! -e "$_cfu_result/source-conflict" ]; then
			comments_safe_path "$cc_dir/source-conflict" || return 1
			rm -f "$cc_dir/source-conflict" || return 1
		fi
	fi
	if [ -f "$cc_dir/delivery" ] && [ "$(comments_field "$cc_dir/delivery" state)" = delivered ] && [ ! -f "$cc_dir/source-baseline.md" ]; then
		comments_delivery_load "$cc_dir" 1 || return 1
		# The caller already applied finish's divergence/--force guard.
		# When undo was requested elsewhere, remove only our carried, unchanged
		# untracked delivery. A tracked file belongs to that other branch.
		if [ "$(git symbolic-ref --quiet --short HEAD || true)" = "$cm_delivery_branch" ]; then
			rm -f "$cm_delivery_path" || return 1
		elif ! git -C "$cm_delivery_root" ls-files --error-unmatch -- .review/comments.md >/dev/null 2>&1; then
			if [ -f "$cm_delivery_path" ]; then
				_cfu_carried_revision=$(git hash-object --no-filters -- "$cm_delivery_path") || return 1
				if [ "$_cfu_carried_revision" != "$_cfu_delivered_revision" ]; then
					comments_error 'Shared prose changed on another branch; preserve it before undoing the finish'; return 1
				fi
			fi
			rm -f "$cm_delivery_path" || return 1
		fi
	fi
	# Code undo returns to a preparation, including when delivery was pending.
	# Its previous output branch is no longer a delivery destination.
	comments_revision "$cc_dir/delivery" >/dev/null || return 1
	rm -f "$cc_dir/delivery"
}

comments_remove_custody() (
	_crc_branch=$1 _crc_completed=$2
	comments_lock_branch "$_crc_branch" || exit 1
	trap 'comments_unlock' 0
	trap 'exit 1' 1 2 15
	[ -n "$cc_session" ] || exit 0
	if [ "$_crc_completed" -eq 1 ] && [ -n "$cc_context" ]; then
		_crc_result=$(comments_result_dir "$cc_context") || exit 1
		# The editable retained generation may be newer than the session kept
		# for undo. Never replace those edits with the stale session copy.
		_crc_session=''
		if [ -n "$_crc_result" ]; then _crc_session=$(comments_field "$_crc_result/manifest" session) || exit 1; fi
		if [ -z "$_crc_result" ] || [ "$_crc_session" != "$cc_session" ]; then comments_publish "$cc_context" "$cc_dir" || exit 1; fi
	fi
	comments_discard_branch "$_crc_branch"
)

# ── Advice: lo que quien tiene el porcelain no necesita ──────────────────────

# advice_enabled
# Whether to print the notes a caller with its own interface does not need. Same
# shape as git's advice.*, one step further out: the three panels reinvoke these
# verbs and forward what they print, so a note offering `git review walkthrough
# guide` lands as a paragraph naming a command that is a button two rows down,
# and telling one note from another on their side would mean parsing human
# output. Advice is one question — does the caller already have this? An offer of
# a command or a flag (it has the button) and state that already travels as a
# porcelain record (it has the row) are advice; everything else the verb has to
# say prints either way. See AGENTS.md "Advice" and decisiones.md §15.2.
#
# Precedence is git's: GIT_REVIEW_ADVICE (what the clients export, one place per
# client) wins over the config key, and unset means on, so a terminal keeps every
# note it has always had.
advice_enabled() {
	case "${GIT_REVIEW_ADVICE-}" in
		0 | false | no) return 1 ;;
		1 | true | yes) return 0 ;;
	esac
	# Read defensively, like every config read here: `git config` exits non-zero
	# on a missing key, and set -e would abort the verb over a key nobody set.
	if [ "$(git config --bool reviewworkflow.advice 2>/dev/null || true)" = "false" ]; then
		return 1
	fi
	return 0
}

# advice_suffix <text>
# The offer half of a mixed note, emitted only when advice is on: the note keeps
# its state and loses its command. A suffix and not a second note because the two
# halves are one sentence — "reviewing X, which differs from your local Y; use
# --local to review what you have checked out" — and the state half must survive.
advice_suffix() {
	if advice_enabled; then
		printf '%s' "$1"
	fi
}

# ── Branch / remote candidates (git review config --porcelain) ────────────────

# candidate_remotes <effective-remote>
# Emit a "remote-candidate<TAB>name<TAB>current" row for every remote `git remote`
# lists. current is 1 only for the effective reviewworkflow.remote (origin when
# unset), so the pick list can put it first without re-deriving it; name is what a
# caller passes back to `config remote`. One `git remote` call and a loop of shell
# built-ins over its output (contracts/config-porcelain.md "Costo").
candidate_remotes() {
	_cr_effective="$1"
	git remote |
		while IFS= read -r _cr_name; do
			[ -n "$_cr_name" ] || continue
			_cr_current=0
			if [ "$_cr_name" = "$_cr_effective" ]; then
				_cr_current=1
			fi
			porcelain_row remote-candidate "$_cr_name" "$_cr_current"
		done
}

# current_branch_init
# Resolve the branch HEAD sits on ONCE per process into $_cur_branch (empty when
# HEAD is detached). Same shape and reason as walk_gitdir_init: a $(...) cannot
# cache anything, and two emitters of one porcelain run want it now
# (candidate_branches, emit_walkthrough_record), so asking twice would spend a
# process per panel refresh on a value that cannot change mid-run.
current_branch_init() {
	if [ -z "${_cur_branch_done:-}" ]; then
		_cur_branch="$(git symbolic-ref --quiet --short HEAD || true)"
		_cur_branch_done=1
	fi
}

# candidate_branches <remote>
# Emit a "candidate<TAB>name<TAB>origin<TAB>current" row for every branch eligible
# to start a review on: every ref in refs/heads/ and refs/remotes/<remote>/, minus
# the three product namespaces (review/, review-saved/, review-fixes/) and
# <remote>/HEAD — exactly what bin/git-review-verbs/start refuses to review, so
# offering them would be offering a guaranteed failure. name has no namespace
# prefix (it is what a caller passes back to start or to config <key>); origin is
# remote|local; current is 1 only for the local branch HEAD sits on — a remote
# copy is never "current".
#
# One for-each-ref call regardless of how many branches exist, not one process per
# branch (contracts/config-porcelain.md "Costo"): the loop below is shell built-ins
# over its output, so the process count stays constant.
candidate_branches() {
	_cb_remote="$1"
	current_branch_init
	_cb_cur="$_cur_branch"
	git for-each-ref --format='%(refname)' refs/heads/ "refs/remotes/$_cb_remote/" |
		while IFS= read -r _cb_ref; do
			case "$_cb_ref" in
			refs/heads/*)
				_cb_name="${_cb_ref#refs/heads/}"
				_cb_origin=local
				;;
			"refs/remotes/$_cb_remote/"*)
				_cb_name="${_cb_ref#refs/remotes/"$_cb_remote"/}"
				_cb_origin=remote
				;;
			*)
				continue
				;;
			esac
			case "$_cb_name" in
			review/* | review-saved/* | review-fixes/* | HEAD)
				continue
				;;
			esac
			_cb_current=0
			if [ "$_cb_origin" = local ] && [ "$_cb_name" = "$_cb_cur" ]; then
				_cb_current=1
			fi
			porcelain_row candidate "$_cb_name" "$_cb_origin" "$_cb_current"
		done
}

# ── Porcelain (machine-readable) output ───────────────────────────────────────
#
# porcelain_row <field> [field...]
# Print one porcelain-format line: the given fields joined by a tab, terminated by
# a newline. The single point that writes a porcelain line — every emitter passes
# its fields through here instead of printf-ing tabs itself, so the separator
# lives in one place. A field the record's mode does not apply to is omitted from
# the call entirely: omit, never blank, never a sentinel
# (contracts/status-porcelain.md, data-model.md).
porcelain_row() {
	_pr_first=1
	for _pr_field in "$@"; do
		if [ "$_pr_first" -eq 1 ]; then
			printf '%s' "$_pr_field"
			_pr_first=0
		else
			printf '\t%s' "$_pr_field"
		fi
	done
	printf '\n'
}

# show_commit <commit> <n> <total>
# Print a commit's diffstat first and its identifying header last, so the header
# stays next to the prompt instead of scrolling off the top when the diffstat is
# long. core.quotePath=false for the same reason as changed_paths: git's default
# would show "src/caf\303\251.js", an escape nobody can paste into an editor.
# Cosmetic here (nothing compares these bytes), but it keeps every path this
# project prints in one shape.
show_commit() {
	git --no-pager -c core.quotePath=false show --stat --format='' "$1"
	printf -- '----\n[%s/%s] %s\n%s\n\n%s\n----\nreview this commit, edit files, then run git review next\n' \
		"$2" "$3" "$(git rev-parse --short "$1")" \
		"$(git show -s --format='%an <%ae>' "$1")" \
		"$(git show -s --format='%s%n%n%b' "$1")"
}

# require_not_finish_conflict
# Refuse verbs that would bank/move/capture the working tree while a finish is
# stopped mid-conflict (reviewresume=conflict). Only finish --resume / --abort
# (and abort of the whole review) are valid exits; next/prev/save would bank
# conflict markers as "edits" or delete the review branch that holds the undo.
# Mirror of the same guard in git review preview.
require_not_finish_conflict() {
	_rnfc_cur="$(git symbolic-ref --quiet --short HEAD || true)"
	if [ "$(git config "branch.$_rnfc_cur.reviewresume" || true)" = "conflict" ]; then
		echo "error: git review finish is mid-conflict; resolve the markers and run git review finish --resume first (or git review finish --abort)" >&2
		exit 1
	fi
}

# require_not_pending_finish
# Refuse verbs that would bank/move/rename a review/* branch while a completed
# finish still holds reviewundohead on it. After finish, HEAD sits on
# review-fixes/* (or the PR) with undo live on review/*; hand-switching back and
# running next/prev/save would desync the cursor/banks and break finish --abort.
# Shared message for save/next/prev so consumers match one diagnostic.
require_not_pending_finish() {
	_rnpf_cur="$(git symbolic-ref --quiet --short HEAD || true)"
	if [ -n "$(git config "branch.$_rnpf_cur.reviewundohead" || true)" ]; then
		echo "error: a previous finish on $_rnpf_cur has not been resolved; run git review finish --abort (or git review abort) first" >&2
		exit 1
	fi
}

# require_clean_work_tree
# Refuse start/compare/continue when the worktree is dirty: tracked changes
# (diff / cached) *or* untracked non-ignored files. finish/save capture untracked
# with `git add -A` as review edits, so letting pre-existing untracked through
# start would absorb junk as if the reviewer wrote it.
require_clean_work_tree() {
	if ! git diff --quiet || ! git diff --cached --quiet ||
		[ -n "$(git ls-files --others --exclude-standard)" ]; then
		echo "error: you have local changes; commit or stash them first" >&2
		exit 1
	fi
}

# apply_review_patch FROM TO [git-apply-args...]
# Diff FROM..TO and apply it through a temp file, never a shell variable:
# capturing a binary patch with command substitution drops its NUL bytes and its
# trailing newline, and git apply then rejects it ("corrupt binary patch").
# Always passes --binary so continue/finish/goto_step get the same safety as
# preview. An empty diff is a no-op success; returns git apply's exit status.
apply_review_patch() {
	_from="$1"
	_to="$2"
	shift 2
	_pf="$(git rev-parse --git-dir)/review-apply.$$"
	git diff --binary "$_from" "$_to" >"$_pf"
	if [ -s "$_pf" ]; then
		if git apply --binary "$@" <"$_pf"; then _rc=0; else _rc=$?; fi
	else
		_rc=0
	fi
	rm -f "$_pf"
	return "$_rc"
}

# entry_noun <count>
# "entry" or "entries" for human messages (avoids the A && B || C plural idiom).
entry_noun() {
	if [ "$1" -eq 1 ]; then
		printf '%s' "entry"
	else
		printf '%s' "entries"
	fi
}

# load_step_review_meta
# Confirm HEAD is on a review/* branch started with --step and load its metadata
# into the globals the caller and goto_step rely on: cur, src, tip, start, count,
# step, commits and total. Exits with a diagnostic on any inconsistency (wrong
# branch, wrong mode, or missing/corrupt metadata).
load_step_review_meta() {
	cur="$(git symbolic-ref --quiet --short HEAD || true)"
	[ -n "$cur" ] || {
		echo "error: not on a branch" >&2
		exit 1
	}
	case "$cur" in
	review/*) ;;
	*)
		echo "error: not on a review/* branch (HEAD is $cur)" >&2
		exit 2
		;;
	esac

	mode="$(git config "branch.$cur.reviewmode" || true)"
	[ "$mode" = "step" ] || {
		echo "error: $cur was not started with git review start --step or a walkthrough" >&2
		exit 1
	}

	src="$(git config "branch.$cur.reviewsource" || true)"
	tip="$(git config "branch.$cur.reviewtip" || true)"
	start="$(git config "branch.$cur.reviewstart" || true)"
	count="$(git config "branch.$cur.reviewcount" || true)"
	step="$(git config "branch.$cur.reviewstep" || true)"

	# A key deleted by a hand-edit (while reviewmode stays "step") would otherwise
	# let set -e kill us silently mid-script; read with || true and report it.
	if [ -z "$src" ] || [ -z "$tip" ] || [ -z "$start" ] || [ -z "$count" ]; then
		if [ -z "$src" ]; then
			echo "error: missing review metadata; was $cur created with git review start? Switch away, then delete it with 'git branch -D $cur'." >&2
		else
			echo "error: missing review metadata; was $cur created with git review start? Discard the review with 'git review abort'." >&2
		fi
		exit 1
	fi

	# Set here too, not left half-applied by mode: a step review does not read a
	# walkthrough, but its verbs share this scope with the walk readers. Keep the
	# asymmetry in mind before giving step a surface that shows a "why" — the
	# context is set but nothing reports it (status emits the draft record only in
	# walk mode), so a step verb that started reading one would show the reviewer's
	# own prose without saying whose it is, the one thing this feature prevents.
	#
	# Through the recorded name, like the walk loader: a compare --step of a
	# remote-tracking branch drafts under the branch's name, and one config read is
	# what keeps the two loaders from disagreeing about whose file it is.
	walk_use_draft "$(walk_review_draft_src "$cur")"

	commits="$(git rev-list --reverse --first-parent --no-merges "$start..$tip")"

	# Guard against a step that maps to no commit (hand-edited metadata): otherwise
	# goto_step's sed yields an empty commit and git rev-parse '^{tree}' crashes
	# mid-move. grep -c exits 1 on a count of 0, which under set -e would abort
	# before the diagnostic below — hence || true (walk does the same).
	total="$(printf '%s\n' "$commits" | grep -c . || true)"
	case "$count" in
	*[!0-9]*)
		echo "error: corrupt review metadata: reviewcount is '$count', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
		;;
	esac
	[ "$count" -ge 1 ] || {
		echo "error: corrupt review metadata: reviewcount is '$count', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
	}
	case "$step" in
	'' | *[!0-9]*)
		echo "error: corrupt review metadata: reviewstep is '$step', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
		;;
	esac
	if [ "$total" -lt 1 ]; then
		echo "error: corrupt review metadata: no commits in range $start..$tip. Discard the review with 'git review abort'." >&2
		exit 1
	fi
	if [ "$step" -lt 1 ] || [ "$step" -gt "$total" ]; then
		echo "error: review step $step out of range (1..$total) — corrupt metadata? Discard the review with 'git review abort'." >&2
		exit 1
	fi
}

# load_step_texts
# Load the subject and the author of every commit in the step sequence into the
# globals `subjects` and `authors` — one line per commit, aligned with `commits`
# by line number. Relies on the globals load_step_review_meta sets (start, tip);
# call it after, never instead. The step verbs that only move the cursor do not
# call it: no use for the text, no reason to pay the two processes.
#
# Two git processes for the whole sequence, not one per commit: on Windows, where
# fork() is emulated, 2N processes is the difference between instant and
# perceptible. Same traversal flags as `commits`, which is what makes the lists
# line up; aligning by line number is safe because neither format can emit an
# inner newline (%s is the first line by definition, and git strips the newline
# out of the ident). If that stopped holding, the symptom would be a subject
# silently paired with the wrong commit.
#
# Both lists keep their trailing newline (append an x, strip it with ${var%x}):
# command substitution strips trailing newlines, so a last commit with an EMPTY
# subject would shorten the list and drop its record -- which a consumer reads as
# "this CLI has no subjects" rather than "this commit has none".
load_step_texts() {
	# shellcheck disable=SC2034  # both are globals for the caller (status), like
	# the ones load_step_review_meta sets; nothing in this file consumes them.
	subjects="$(git log --reverse --first-parent --no-merges --format=%s "$start..$tip"; printf x)"
	subjects="${subjects%x}"
	# shellcheck disable=SC2034  # idem.
	authors="$(git log --reverse --first-parent --no-merges --format='%an <%ae>' "$start..$tip"; printf x)"
	authors="${authors%x}"
}

# goto_step <target>
# Move a --step review to step <target>: bank the current commit's edits, reset
# clean to the target commit, restore the target's previously banked edits (if
# any), then soft-reset so its diff is staged. Relies on the globals set by
# load_step_review_meta (cur, src, count, step, commits). On apply failure the
# working tree is rolled back to the step we left (cursor unchanged) so the
# session is not left half-moved on the target with the origin already banked.
goto_step() {
	target="$1"
	prev_step="$step"
	cstep="$(printf '%s\n' "$commits" | sed -n "${step}p")"
	git add -A
	tree="$(git write-tree)"
	if [ "$tree" != "$(git rev-parse "$cstep^{tree}")" ]; then
		edit="$(git commit-tree "$tree" -p "$cstep" -m "review edits step $step")"
		git update-ref "refs/review-edits/$src/$step" "$edit"
	else
		# Reverting the step back to a clean tree must clear any edits we banked
		# earlier, or they resurrect on the next visit / at git review finish.
		git update-ref -d "refs/review-edits/$src/$step" 2>/dev/null || true
	fi
	ctarget="$(printf '%s\n' "$commits" | sed -n "${target}p")"
	git reset -q --hard "$ctarget"
	ref="refs/review-edits/$src/$target"
	if git rev-parse --verify --quiet "$ref" >/dev/null; then
		# No --3way here: it implies --index and would leave banked edits staged,
		# so git diff (unstaged) goes empty and the step UI/tests lose the edit.
		# Temp-file apply still keeps binary hunks intact.
		if ! apply_review_patch "${ref}^" "$ref"; then
			echo "error: could not restore banked edits for step $target" >&2
			# Roll back: hard-reset to the origin step and re-apply its bank.
			git reset -q --hard "$cstep"
			pref="refs/review-edits/$src/$prev_step"
			if git rev-parse --verify --quiet "$pref" >/dev/null; then
				apply_review_patch "${pref}^" "$pref" || true
			fi
			git reset -q --soft "$cstep^"
			exit 1
		fi
	fi
	git reset -q --soft "$ctarget^"
	git config "branch.$cur.reviewstep" "$target"
	show_commit "$ctarget" "$target" "$count"
}

# ── Walkthrough (walk) mode helpers ───────────────────────────────────────────
#
# A walkthrough is a guided reading order over a PR, authored as a committed
# sidecar (.review/walkthrough.md). Walk mode is the same whole-PR review (the
# diff staged and editable) plus a reading cursor over it: nothing here stages,
# resets or banks anything, only a cursor config key moves.

# resolve_lower_bound <start> <baseref> <tip>
# Same fold decision as fold_lower, but never creates a commit: prints <start>
# (a commit) when nothing needs folding, or the merge-tree tree OID when base
# content must be folded into the lower bound. Read-only probes (config
# --porcelain offers) use this so they do not leave dangling commit-tree objects
# in the object DB. git diff / walk_sequence accept a tree OID as either side.
resolve_lower_bound() {
	_rlb_start="$1"
	_rlb_baseref="$2"
	_rlb_tip="$3"
	_rlb_lower="$_rlb_start"
	if [ -n "$_rlb_baseref" ]; then
		_rlb_mb="$(git merge-base "$_rlb_baseref" "$_rlb_tip" 2>/dev/null || true)"
		if [ -n "$_rlb_mb" ] && [ "$_rlb_mb" != "$_rlb_tip" ] &&
			! git merge-base --is-ancestor "$_rlb_mb" "$_rlb_start"; then
			if _rlb_tree="$(git merge-tree --write-tree "$_rlb_start" "$_rlb_mb" 2>/dev/null)"; then
				_rlb_lower="$_rlb_tree"
			else
				echo "note: could not exclude merged base content from the review diff" >&2
			fi
		fi
	fi
	printf '%s\n' "$_rlb_lower"
}

# fold_lower <start> <baseref> <tip>
# Compute a review's lower bound (exclusive). Normally it is <start>, but if the
# base branch was merged into the PR, fold that already-merged base content into
# the lower bound so base-derived changes are not shown as part of the review.
# Prints the resulting commit-ish. When folding is needed, materializes a real
# commit (commit-tree) so start can soft-reset onto it. A no-op (prints <start>)
# when there is nothing to fold, when <baseref> is empty, or on a git without
# merge-tree. Shared by start and walkthrough init/build.
fold_lower() {
	_fl_start="$1"
	_fl_baseref="$2"
	_fl_tip="$3"
	_fl_bound="$(resolve_lower_bound "$_fl_start" "$_fl_baseref" "$_fl_tip")"
	if [ "$_fl_bound" != "$_fl_start" ]; then
		_fl_lower="$(git commit-tree "$_fl_bound" -p "$_fl_start" -m 'review lower bound')"
	else
		_fl_lower="$_fl_start"
	fi
	printf '%s\n' "$_fl_lower"
}

# changed_paths <lower> <tip>
# The paths a review range changes, one per line, verbatim — the git side of every
# path comparison in this project (walkthrough entries, the drift check, the
# uncovered-files note). core.quotePath=false is the whole point of the helper:
# with git's default any path holding a non-ASCII byte comes out escaped and
# quoted ("src/caf\303\251.js") while the same path written in a walkthrough is
# literal, so the two never compare equal — the entry drops out of the reading
# order in silence and build reports the same file as both missing and extra.
# Same shape as a CRLF sidecar (see walk_normalize), except it hides from anyone
# whose repo is ASCII-only rather than from anyone on Windows. A path holding a
# '"' or a '\' is still quoted either way; both are illegal on Windows and
# vanishingly rare elsewhere, and unquoting them here would mean re-implementing
# git's C escaping in awk.
changed_paths() {
	git -c core.quotePath=false diff "${3:---name-only}" "$1" "$2"
}

# range_files <tip> <lower>
# The files a review's range touches, in git's own order — the same
# changed_paths(lower, tip) every other reader of "what does this review touch"
# makes, wrapped so the argument order is not repeated and inverted at each call
# site. whole mode's file listing is this and nothing more: HEAD sits at the lower
# bound in every mode (start's git reset --soft), so these are the endpoints walk
# already reads.
#
# 2>/dev/null || true folded in here rather than left to each caller: a range that
# will not diff (an unresolvable bound, reachable from start/compare before the
# review's tip is fixed) yields no paths, so no entry intersects and the caller
# degrades — it must never abort the review under set -eu.
range_files() {
	changed_paths "$2" "$1" 2>/dev/null || true
}

# commit_files <sha>
# Paths a single commit touches, one per line, in git's own order — the step-mode
# inventory of "what does this commit change". Name-only (no status letter, no
# patch): clients open each file's diff themselves; status only needs the list
# to draw the panel. Same path rules as changed_paths (core.quotePath=false).
# --root so an empty-tree parent still lists the commit; 2>/dev/null || true so a
# bad/unresolvable SHA yields zero paths under set -eu instead of aborting.
commit_files() {
	git -c core.quotePath=false diff-tree --no-commit-id --name-only -r --root "$1" 2>/dev/null || true
}

# walk_normalize  (stdin: text)
# Make an authored walkthrough's bytes comparable, whatever wrote it. Every reader
# below matches on whole lines, so an invisible byte at either end makes a path
# differ from git's, no entry intersects the range, and the reviewer silently
# loses walk mode. Two such bytes, both added by a Windows editor on its own:
#
#   * a line-final carriage return (CRLF, an author with core.autocrlf on). Only
#     the line-final CR goes; a CR mid-line is content. It bites only on
#     Linux/macOS, because the MSYS awk swallows it — the case a Windows author
#     cannot see.
#   * a UTF-8 BOM on the first line (Notepad, PowerShell Out-File and >). It hides
#     the "# Walkthrough" heading from walk_preamble, which prints it as the
#     author's heads-up and lets build bake the duplicate in; on a walkthrough
#     opening straight with an entry it hides that entry from walk_parse.
#
# The BOM is matched as a string, not a regex escape: the escape is not portable
# across the three awks in CI, while index/substr/length agree whether the awk
# counts bytes or characters.
walk_normalize() {
	awk -v bom="$(printf '\357\273\277')" '
		NR == 1 && index($0, bom) == 1 { $0 = substr($0, length(bom) + 1) }
		{ sub(/\r$/, ""); print }
	'
}

# walk_gitdir_init
# Resolve the working tree's gitdir once for the life of the process, into
# _walk_gitdir; every draft path below derives from it.
#
# It has to be resolved in the caller's own shell, not lazily inside the path
# helpers: those run as "$(walk_draft_path ...)", and an assignment made inside a
# command substitution dies with its subshell, so the cache would never be read
# and every walk_read would pay another git process — a plain status in walk mode
# called this four times.
#
# walk_use_draft calls it, covering every verb with an active review; the verbs
# that build a draft path without setting a draft context (list, save, continue,
# forget) call it themselves. Caching is safe because no verb ever changes
# directory: the value may be relative (".git"), which a chdir would silently
# invalidate.
walk_gitdir_init() {
	[ -n "${_walk_gitdir:-}" ] || _walk_gitdir="$(git rev-parse --git-dir)"
}

# walk_gitdir_abs_init
# The gitdir again, this time ABSOLUTE, resolved once into _walk_gitdir_abs. Same
# shape and reason as walk_gitdir_init: an assignment made inside a "$(...)" dies
# with its subshell, so the cache would never be read.
#
# Separate from _walk_gitdir rather than replacing it: that one may legitimately
# be relative (".git" from the top level) and every draft path built from it is
# opened by this process, where relative is fine and cheaper. This one exists for
# the one job that needs more — handing a path to a client that will open it from
# somewhere else — so it is only resolved when there is a draft to report.
walk_gitdir_abs_init() {
	[ -n "${_walk_gitdir_abs:-}" ] || _walk_gitdir_abs="$(git rev-parse --absolute-git-dir)"
}

# walk_draft_progress <path>...
# Emit "<path><TAB><annotated><TAB><total><TAB><source><TAB><range><TAB><tip>"
# for EVERY path given, in the order given. ONE awk for all of them, never one
# per draft: this runs inside config --porcelain, which the panel invokes on
# every refresh, and that path's process count is what the panel's latency is
# measured in (the same rule that produced walk_entry_fields).
#
# Definitions, from data-model.md:
#   total      every entry heading the file declares, numbered and "## ?." alike,
#              PLUS the "## Heads-up" section whenever it holds anything at all
#   annotated  an entry with BOTH a numeric position and a resolved why -- at
#              least one non-blank body line that is not "> key" or "> at: ", and
#              no line opening with "<!-- why". The heads-up is annotated once no
#              "<!-- heads-up" placeholder is left in the preamble.
#   source     remote | local | offline, and range full | delta, read off the
#              "Generated with:" line of the instruction block, the only place
#              that datum lives. Both are "unknown" when the block is not there,
#              which is legal: deleting it by hand is allowed.
#   tip        the SHA the block records as the range's upper bound, or empty when
#              the block is gone or its value is not a SHA. Same 40-hex rule as
#              walk_sidecar_block_tip, read here because the caller that needs it
#              (emit_draft_records) has N files and a one-process budget.
#
# The count is over the FILE, never crossed with the range: a drifted draft still
# reports its progress, and annotated == total promises nothing about --build.
#
# The heads-up counts as a unit of the pair because build rejects its placeholder
# the way it rejects an unfilled why. Left out, the commonest skeleton -- one file
# in the range, its heads-up untouched -- reported 1/1, so the panel drew the
# reading order as finished and the build behind Validate and start died on the
# placeholder. It counts only when the section holds SOMETHING, so deleting the
# whole section (legal) goes from 1/2 to 1/1 instead of sitting one short of a
# total it can no longer reach. Matched with build's own anchored rule over the
# preamble, so a comment that outlived its heading still counts.
#
# Two deliberate shapes: per-file closing is FNR == 1 plus END, never ENDFILE (a
# gawk extension -- CI runs mawk and BSD awk too); and END walks ARGV instead of
# printing as it goes, so a ZERO-BYTE file still gets a line. awk runs no rule and
# assigns no FILENAME for an empty file, which is exactly the state a freshly
# created draft is in -- the one that most needs listing to be opened or
# discarded.
walk_draft_progress() {
	awk -v bom="$(printf '\357\273\277')" '
		function close_entry() {
			if (inentry && numbered && prose && !whyc) ann[cur]++
			inentry = 0
		}
		# The heads-up is settled once per FILE and not at the heading that ends
		# its section, because the placeholder rule it mirrors is a preamble-wide
		# one: build looks for "<!-- heads-up" anywhere before the first entry,
		# so a comment that outlived its own heading still counts against it.
		function close_file() {
			close_entry()
			if (huseen || huph) {
				tot[cur]++
				if (!huph) ann[cur]++
			}
			huopen = 0
			huseen = 0
			huph = 0
		}
		FNR == 1 {
			close_file()
			cur = FILENAME
			seen[cur] = 1
			ann[cur] = 0
			tot[cur] = 0
			src[cur] = "unknown"
			rng[cur] = "unknown"
			tp[cur] = ""
			inblock = 0
			preamble = 1
			if (index($0, bom) == 1) $0 = substr($0, length(bom) + 1)
		}
		{ sub(/\r$/, "") }
		# The "Generated with:" line is read only from inside the instruction
		# block. Anchoring on the block rather than on the text keeps a why that
		# happens to quote the line from being mistaken for it.
		index($0, "<!-- git-review-range:") == 1 { inblock = 1 }
		inblock && index($0, "-->") { inblock = 0 }
		# The upper bound of the range this file was last written against, read
		# from inside the block for the same reason as the flags, and validated to
		# 40 hex exactly as walk_sidecar_block_tip validates it: the value ends up
		# compared against a recorded SHA, so prose that happens to sit on a "tip"
		# line must not become one. A match plus length() rather than an interval
		# {40}, which mawk and BSD awk do not all accept.
		inblock && $1 == "tip" && $2 ~ /^[0-9a-f]+$/ && length($2) == 40 {
			tp[cur] = $2
			next
		}
		inblock && $0 ~ /^[ \t]*Generated with: / {
			flags = $0
			sub(/^[ \t]*Generated with: /, "", flags)
			if (index(flags, "--offline")) src[cur] = "offline"
			else if (index(flags, "--local")) src[cur] = "local"
			else src[cur] = "remote"
			if (index(flags, "--delta")) rng[cur] = "delta"
			else rng[cur] = "full"
			next
		}
		/^## / {
			close_entry()
			line = substr($0, 4)
			sub(/[ \t]+$/, "", line)
			if (match(line, /^[0-9]+\. /)) {
				tot[cur]++
				inentry = 1
				numbered = 1
				prose = 0
				whyc = 0
				preamble = 0
				huopen = 0
			} else if (match(line, /^\?\. /)) {
				tot[cur]++
				inentry = 1
				numbered = 0
				prose = 0
				whyc = 0
				preamble = 0
				huopen = 0
			} else {
				# Every other heading closes the heads-up section without being
				# one. Only the heading the skeleton writes opens it, matched as
				# loosely about case as the readers are about the key marker.
				huopen = (preamble && tolower(line) == "heads-up")
			}
			next
		}
		# Build refuses on the anchored comment over the preamble as a whole, so
		# this looks for it there and not inside the section.
		preamble && index($0, "<!-- heads-up") == 1 { huph = 1 }
		huopen && $0 ~ /[^ \t]/ { huseen = 1 }
		inentry {
			if (index($0, "<!-- why") == 1) { whyc = 1; next }
			# As lenient about spelling as the build-time key_re, and for the
			# opposite reason from walk_is_key: that one reads a BUILT
			# walkthrough, where build has already canonicalised the marker, so
			# it can insist on "> key". This counts DRAFTS, which nobody has
			# built yet, so "> Key" is still there in the spelling its author
			# used -- and matching only the lower-case form reported an entry
			# whose whole body is the marker as annotated.
			if ($0 ~ /^>[ \t]*[Kk][Ee][Yy][ \t]*$/) next
			if (index($0, "> at: ") == 1) next
			if ($0 ~ /[^ \t]/) prose = 1
		}
		END {
			close_file()
			for (i = 1; i < ARGC; i++) {
				f = ARGV[i]
				if (f in seen)
					printf "%s\t%d\t%d\t%s\t%s\t%s\n", f, ann[f], tot[f], src[f], rng[f], tp[f]
				else
					printf "%s\t0\t0\tunknown\tunknown\t\n", f
			}
		}
	' "$@"
}

# walk_reviewed_markers
# Every recorded last-reviewed tip in this repository, as the raw "<key> <sha>"
# lines git config prints, in ONE process: both sections at once with an
# alternation, because a draft needs only one of them and which one depends on the
# flags it was generated with -- two calls would be two processes on a path that
# runs in every panel refresh.
#
# What a marker means (bin/git-review-verbs/start writes it, abort and a clean
# without a completed finish roll it back): the tip of <src> that your last
# COMPLETED review of it covered.
walk_reviewed_markers() {
	git config --get-regexp '^reviewworkflow(local)?[.].*[.]reviewed$' 2>/dev/null || true
}

# walk_draft_state <src> <source> <tip> <annotated> <total> <markers>
# Set _wds_out to "reviewed" when this reading order is written through AND a
# completed review of <src> covered the very tip it was generated against; to
# "fresh" otherwise. Answers in a VARIABLE rather than on stdout, unlike almost
# everything else here: the one caller runs it once per draft, and a "$(...)"
# would fork a subshell each time -- the same per-draft cost the single awk
# exists to avoid, paid again one layer up.
#
# It is the draft's own tip that is compared, not the branch's tip now: a draft
# regenerated after the review covers a range nobody has read yet, and one whose
# branch moved on is drifted, not "already reviewed". The flavour has to match
# too -- a --local draft is answered by reviewworkflowlocal and a remote one by
# reviewworkflow, exactly as start chooses between them; crossing them would
# report a draft as read because the OTHER copy of the branch was. An "unknown"
# source (the block deleted by hand, which is legal) or a missing tip answers
# "fresh": nothing can be proved, and fresh offers more, not less.
#
# A case glob, not grep: this runs once per draft. Safe as an exact test because
# git refuses to create a ref whose name holds '*', '?' or '['.
walk_draft_state() {
	_wds_src="$1"
	_wds_source="$2"
	_wds_tip="$3"
	_wds_ann="$4"
	_wds_tot="$5"
	_wds_marks="$6"
	_wds_out=fresh
	[ -n "$_wds_tip" ] || return 0
	# An order with entries still unwritten is not one you finished with, whatever
	# the marker says: the clients draw a spent row without the two controls that
	# fill it in and start it, and a --force rewrite over a branch that has not
	# moved lands on the very tip the marker records -- so without this the blank
	# skeleton the reviewer just asked for would be folded away with no way to make
	# progress on it. Same test the three panels use for "filled", at zero extra
	# cost (the awk that read the file counted the pair). total == 0 is "this file
	# declares no entry", never "complete".
	[ "$_wds_tot" -gt 0 ] && [ "$_wds_ann" -ge "$_wds_tot" ] || return 0
	case "$_wds_source" in
	remote) _wds_key="reviewworkflow.$_wds_src.reviewed" ;;
	local | offline) _wds_key="reviewworkflowlocal.$_wds_src.reviewed" ;;
	*) return 0 ;;
	esac
	case "
$_wds_marks
" in
	*"
$_wds_key $_wds_tip
"*) _wds_out=reviewed ;;
	esac
}

# walk_each_draft <callback>
# Run <callback> <src> <path> <annotated> <total> <source> <range> <state> once
# for every loose draft -- every file in the ACTIVE namespace, which is every
# reading order the reviewer started and has not paused (git review save moved a
# paused one to review-saved-walkthrough/, which walk_draft_list does not walk).
#
# One enumeration for the two surfaces that need it -- the porcelain records and
# forget --draft --reviewed -- so the gitdir prefix and the state rule cannot
# exist twice and disagree about which drafts exist and which are spent.
#
# The callback runs inside a pipeline, so it is downstream of a subshell: it can
# print, and it cannot hand anything back in a variable.
#
# Cost, because this runs on every panel refresh without a review: walk_draft_list
# is 0 processes (glob recursion, all builtin); walk_gitdir_abs_init,
# walk_draft_progress and walk_reviewed_markers are 1 each, only when there is
# something to report. The last buys <state> for ALL the drafts at once.
#
# The empty case has to return BEFORE all of them, and not as an optimisation:
# awk with no file arguments reads standard input and blocks forever, and a
# repository with no drafts is the commonest case there is.
walk_each_draft() {
	_wed_cb="$1"
	_wed_srcs="$(walk_draft_list)"
	[ -n "$_wed_srcs" ] || return 0

	walk_gitdir_abs_init
	# Positional parameters as the argument vector: a branch name cannot hold a
	# space (git forbids it), but the gitdir path can, so the paths are never
	# passed through word splitting.
	set --
	while IFS= read -r _wed_src; do
		[ -n "$_wed_src" ] || continue
		set -- "$@" "$_walk_gitdir_abs/review-walkthrough/$_wed_src.md"
	done <<EOF
$_wed_srcs
EOF
	[ "$#" -gt 0 ] || return 0

	_wed_marks="$(walk_reviewed_markers)"
	# <src> comes back off the path with two parameter expansions rather than out
	# of awk: peeling the gitdir prefix and the .md inside awk would mean doing it
	# for a <src> that can hold '/', where here it is free and exact -- this is
	# the very prefix the loop above glued on.
	walk_draft_progress "$@" | while IFS="$(printf '\t')" read -r _wed_path _wed_ann _wed_tot _wed_source _wed_range _wed_tip; do
		[ -n "$_wed_path" ] || continue
		_wed_name="${_wed_path#"$_walk_gitdir_abs/review-walkthrough/"}"
		_wed_name="${_wed_name%.md}"
		walk_draft_state "$_wed_name" "$_wed_source" "$_wed_tip" \
			"$_wed_ann" "$_wed_tot" "$_wed_marks"
		"$_wed_cb" "$_wed_name" "$_wed_path" "$_wed_ann" "$_wed_tot" \
			"$_wed_source" "$_wed_range" "$_wds_out"
	done
}

# emit_draft_records
# One porcelain "draft" record per loose draft. See walk_each_draft for what is
# walked, what it costs and why the empty case returns early.
_emit_draft_row() {
	porcelain_row draft "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

emit_draft_records() {
	walk_each_draft _emit_draft_row
}

# walk_reviewed_draft_list
# The <src> of every loose draft whose state is "reviewed", one per line: the
# reading orders whose review is over. The inferred set behind
# git review forget --draft --reviewed.
_reviewed_draft_row() {
	[ "$7" = reviewed ] || return 0
	printf '%s\n' "$1"
}

walk_reviewed_draft_list() {
	walk_each_draft _reviewed_draft_row
}

# walk_draft_path <src>
# Where the reviewer's own walkthrough for <src> lives while a review is in play:
# inside the working tree's gitdir, per AGENTS.md's prose-files table (invisible
# to git status, start's dirty check and finish's git add -A). Same idiom as
# COMMIT_EDITMSG/MERGE_MSG. A branch name holding '/' becomes a subdirectory, as
# it does under refs/; callers that write must mkdir -p.
#
# --git-dir (not --git-common-dir): a review is per working tree, so is its draft.
walk_draft_path() {
	walk_gitdir_init
	printf '%s/review-walkthrough/%s.md' "$_walk_gitdir" "$1"
}

# walk_saved_draft_path <src>
# The same draft once git review save has put it aside with the paused review.
# Mirrors refs/review-saved-edits/ exactly: paused work travels with the review
# it belongs to, and the reviewer learns one rule instead of two.
walk_saved_draft_path() {
	walk_gitdir_init
	printf '%s/review-saved-walkthrough/%s.md' "$_walk_gitdir" "$1"
}

# walk_draft_list
# Every draft in the active namespace, as its <src> (a branch name), one per
# line. Nothing at all when the namespace does not exist. Used by
# git review forget --draft --all, the one command that has to enumerate them.
#
# Recursion over globs rather than find: a branch name holding '/' is a
# subdirectory here, so a single-level glob would miss every namespaced branch,
# and find(1) has no other user in this suite — its -empty/-delete are outside
# POSIX, and under Git Bash a stray PATH resolves it to Windows' own find.exe.
walk_draft_list() {
	walk_gitdir_init
	_wdl_root="$_walk_gitdir/review-walkthrough"
	[ -d "$_wdl_root" ] || return 0
	_walk_draft_list_dir "$_wdl_root" ""
}

# walk_saved_draft_list
# The same enumeration over the archived namespace, as <src> names. Its only
# caller is forget --draft --all, for entries no paused review claims: an archive
# entry normally belongs to a review-saved/<src> branch (restored by continue),
# but if that branch is deleted by hand the file becomes reachable from nothing —
# forget --saved needs the ref, and clean is hands-off in there by design.
walk_saved_draft_list() {
	walk_gitdir_init
	_wdl_root="$_walk_gitdir/review-saved-walkthrough"
	[ -d "$_wdl_root" ] || return 0
	_walk_draft_list_dir "$_wdl_root" ""
}

# _walk_draft_list_dir <dir> <prefix>  (walk_draft_list's recursion)
# The loop variables are reused by the nested call on purpose: each is reassigned
# at the top of every iteration and never read across the recursive call, while
# <dir>/<prefix> are positional parameters, which each call frame keeps its own.
_walk_draft_list_dir() {
	for _wdl_entry in "$1"/*; do
		# An unmatched glob stays literal in POSIX sh; -e is what tells the two
		# apart, and it also skips a dangling symlink.
		[ -e "$_wdl_entry" ] || continue
		_wdl_name="${_wdl_entry##*/}"
		if [ -d "$_wdl_entry" ]; then
			_walk_draft_list_dir "$_wdl_entry" "$2$_wdl_name/"
		elif [ -f "$_wdl_entry" ]; then
			case "$_wdl_name" in
			*.md) printf '%s%s\n' "$2" "${_wdl_name%.md}" ;;
			esac
		fi
	done
}

# walk_use_draft <src>
# Point the walkthrough readers at <src>'s local draft, if it has one.
#
# The context travels in a variable, not an argument: walk_read takes a
# commit-ish, not a branch, and neither do the eleven readers stacked on top of
# it, so threading a parameter would touch every signature and call site.
# load_walk_review_meta and load_step_review_meta call this themselves, so every
# verb with an active review inherits it; readers resolving a source outside a
# review (start, compare, emit_reading_offers, walkthrough draft) call it
# directly.
walk_use_draft() {
	walk_draft_src="$1"
	# Here rather than in walk_draft_path: this runs in the verb's own shell,
	# where the resolved gitdir survives to be reused (see walk_gitdir_init).
	walk_gitdir_init
}

# walk_review_draft_src <review-branch>
# The name the draft of the review on <review-branch> lives under, as recorded by
# the verb that created it (branch.<rb>.reviewdraft) — the only function that
# reads it, so a review cannot end up with two names for its own draft. Never
# re-derive this at a call site instead: a creator and a reader disagreeing here
# is what once made start report no draft over prose the reviewer had just
# written.
#
# Not always the review's source: a compare of a remote-tracking branch reviews
# "origin/feature/x" but drafts for "feature/x", since the draft belongs to the
# branch, not the ref you named it by. Falls back to reviewsource for reviews
# created before this key existed, matching what readers derived back then.
walk_review_draft_src() {
	_wrds_name="$(git config "branch.$1.reviewdraft" || true)"
	if [ -z "$_wrds_name" ]; then
		_wrds_name="$(git config "branch.$1.reviewsource" || true)"
	fi
	printf '%s' "$_wrds_name"
}

# walk_saved_draft_filed <saved-branch>
# Whether <saved-branch> is the review that filed the archived draft under its
# name -- the answer git review save recorded (branch.<saved>.reviewdraftfiled)
# when it paused the review.
#
# The name alone cannot answer it: a draft belongs to a branch, so two reviews of
# one branch (e.g. a draftless feature/x paused first, a drafted compare of
# origin/feature/x paused after) can both sit over one archived file that only
# the second wrote. Answering "mine" for both used to send continue to the wrong
# review's prose, forget --saved to destroy prose it never wrote, and list to
# badge a file that was not its.
#
# Absent on reviews paused before the key existed; for those "the file under your
# name is yours" is what every reader assumed anyway, so they keep working across
# the upgrade.
walk_saved_draft_filed() {
	case "$(git config "branch.$1.reviewdraftfiled" || true)" in
	1 | "") return 0 ;;
	esac
	return 1
}

# walk_saved_draft_claims
# Every paused review that owns an archived draft, as "<src><TAB><review-branch>",
# one per line: the <src> is the name the review recorded, the name its draft is
# filed under in review-saved-walkthrough/.
#
# Exists because that name and the branch's own can differ: a compare of a
# remote-tracking branch pauses as review-saved/origin/feature/x but its draft is
# feature/x's, so testing for refs/heads/review-saved/<file name> answers no for
# exactly those reviews — which once let forget --draft --all sweep a live
# paused review's draft, and save overwrite it. Ask each paused review what it
# claims instead, the same question walk_review_draft_src answers elsewhere.
#
# A review that filed nothing claims nothing (walk_saved_draft_filed): it must
# not stop save from replacing that file or forget --draft --all from sweeping
# it, same as it does not restore it at continue. One rule, all four surfaces.
walk_saved_draft_claims() {
	git for-each-ref --format='%(refname:short)' refs/heads/review-saved/ |
		while IFS= read -r _wsc_rb; do
			[ -n "$_wsc_rb" ] || continue
			walk_saved_draft_filed "$_wsc_rb" || continue
			_wsc_name="$(walk_review_draft_src "$_wsc_rb")"
			[ -n "$_wsc_name" ] || continue
			printf '%s\t%s\n' "$_wsc_name" "$_wsc_rb"
		done
}

# walk_draft_body <src>
# Print <src>'s draft, normalised, or nothing (non-zero rc) when <src> has no
# draft in force. "In force" and "the file exists" are not the same thing: an
# empty draft, or one holding only whitespace, has no reading order and must
# behave exactly as an absent one — a bare file test used to answer this, and an
# empty file then shadowed the author's walkthrough while every caller believed
# one existed (start landed in whole with no note, --keys reported no entries on
# a PR that had them).
#
# The single place this rule is written, so walk_read's precedence and
# walk_is_draft's badge cannot drift apart over the same file.
#
# -s before reading: zero bytes is the ordinary shape of this (an editor opened
# and closed, a redirect, an interrupted write), and ruling it out costs nothing.
walk_draft_body() {
	_wdb_path="$(walk_draft_path "$1")"
	[ -f "$_wdb_path" ] || return 1
	[ -s "$_wdb_path" ] || return 1
	# Redirection, not git show: one process fewer than the sidecar path below.
	_wdb_body="$(walk_normalize <"$_wdb_path")"
	case "$_wdb_body" in
	*[![:space:]]*)
		printf '%s\n' "$_wdb_body"
		return 0
		;;
	esac
	return 1
}

# walk_is_draft <src>
# True when <src>'s review is reading the reviewer's own draft rather than the
# author's committed walkthrough — the question behind the "(draft)" suffix in
# status and the draft record in status --porcelain.
#
# Answered by walk_draft_body, the same rule walk_read applies when picking one
# over the other; it costs one process where a bare file test once let status
# say "walk (draft)" over the author's own prose. list and the start assistant
# deliberately keep asking the cheaper question instead (walk_has_draft_file):
# for them a draft file that exists is theirs to handle, empty or not, because
# they report custody, not what is being read.
walk_is_draft() {
	walk_draft_body "$1" >/dev/null
}

# walk_has_draft_file <src>
# Whether a draft file exists for <src> at all — custody, not what is being read.
# The two questions came apart the moment an empty draft stopped counting as a
# reading order: list has to badge a file it is responsible for handing to
# forget --saved, the start assistant has to offer to reopen one, and start has to
# be able to say "yours is empty" about a file walk_is_draft now denies. A file
# test and no process of its own, which is what keeps it usable on those paths.
walk_has_draft_file() {
	[ -f "$(walk_draft_path "$1")" ]
}

# walk_read <tip>
# Print the walkthrough in force, or nothing (non-zero rc) if there is none.
# Never aborts the caller: used in conditions and command substitutions.
#
# Precedence: the reviewer's own draft for the source branch first, the
# walkthrough committed at <tip> second. The single point where walkthrough
# content enters the readers — hence why line-ending normalisation lives here,
# and why every reader (next, prev, status --why, compare, --keys, the panel)
# gets a draft with no change of its own. Consulted only when a caller has named
# the source with walk_use_draft; unset, this behaves exactly as it always did.
walk_read() {
	if [ -n "${walk_draft_src:-}" ] && _wr_body="$(walk_draft_body "$walk_draft_src")"; then
		printf '%s\n' "$_wr_body"
		return 0
	fi
	_wr_content="$(git show "$1:.review/walkthrough.md" 2>/dev/null)" || return 1
	printf '%s' "$_wr_content" | walk_normalize
}

# walk_parse  (stdin: walkthrough content)
# Emit one "order<TAB>path" line per numbered entry ("## N. path"), in file order.
# The intro heading, skeleton entries ("## ?. path") and any other line are
# ignored — leniency is deliberate: the file was already validated by
# "git review walkthrough build", so a stray line must degrade the review, never
# crash it.
#
# Trims trailing whitespace off the path, one of the two normalization points
# AGENTS.md's "Walk y walkthrough" describes (see also walk_normalize): an
# invisible trailing space makes the entry compare unequal to git's path and
# silently drops it from the reading order. Costs the ability to annotate a file
# whose name really ends in a space (legal on Linux, unwritable on Windows).
walk_parse() {
	awk '
		/^## / {
			line = $0
			sub(/^## /, "", line)
			if (match(line, /^[0-9]+\. /)) {
				ord = substr(line, 1, RLENGTH - 2)
				path = substr(line, RLENGTH + 1)
				sub(/[ \t]+$/, "", path)
				# A heading with a number but no path ("## 1. ") is not an entry;
				# emitting it would put an empty path into the drift comparison.
				if (path != "") printf "%s\t%s\n", ord, path
			}
		}
	'
}

# walk_body <path>  (stdin: walkthrough content)
# Print the body of the entry whose path is <path> verbatim — every line after
# its "## N. <path>" (or "## ?. <path>") header, up to the next "## " header or
# EOF. Empty when the path has no entry. The header's path is trimmed exactly as
# walk_parse trims it, so a <path> that came from walk_parse still finds its body.
walk_body() {
	awk -v want="$1" '
		/^## / {
			line = $0
			sub(/^## /, "", line)
			if (sub(/^[0-9]+\. /, "", line) || sub(/^\?\. /, "", line)) {
				sub(/[ \t]+$/, "", line)
				cur = (line == want)
			} else {
				cur = 0
			}
			next
		}
		cur { print }
	'
}

# walk_preamble  (stdin: walkthrough content)
# Print the author's preamble: everything between the "# Walkthrough" heading and
# the first entry, with HTML comments stripped and leading/trailing blank lines
# trimmed. This is where the "## Heads-up" note lives — what is delicate in this
# PR, read before the first file. Comments are dropped because the init skeleton
# writes its instructions as one, and those are scaffolding, not content. Prints
# nothing when what remains is empty or headings only (an author who deleted the
# placeholder without writing anything leaves a bare "## Heads-up" behind).
walk_preamble() {
	awk '
		/^## / {
			line = $0
			sub(/^## /, "", line)
			if (line ~ /^([0-9]+|\?)\. /) exit
		}
		{
			if (skip) { if (index($0, "-->")) skip = 0; next }
			if (index($0, "<!--")) { if (index($0, "-->") == 0) skip = 1; next }
			if ($0 ~ /^# /) next
			buf[++n] = $0
			if ($0 !~ /^#/ && $0 !~ /^[ \t]*$/) prose = 1
		}
		END {
			if (!prose) exit
			s = 1; while (s <= n && buf[s] ~ /^[ \t]*$/) s++
			e = n; while (e >= s && buf[e] ~ /^[ \t]*$/) e--
			for (k = s; k <= e; k++) print buf[k]
		}
	'
}

# ── The instruction block ─────────────────────────────────────────────────────
#
# A walkthrough's skeleton is filled in by somebody who is not looking at the PR
# — usually an agent, from a working tree that holds the wrong content for the
# job. The block below says, in objects rather than words, which range the
# reading order is about and how to see it.
#
# Two functions because generating and consuming are different jobs: init, draft
# and the canonical rewrite emit one (walk_emit_prompt_block), and the rewrite
# also has to swallow the incoming one (walk_prompt_block) so it is regenerated
# rather than carried forward.

# walk_emit_prompt_block <tip> <lower> <tip-label> <lower-kind> <situation> <flags> [<delta-branch>]
# Print the instruction block for a walkthrough skeleton. The ONE generator: the
# author's sidecar and the reviewer's draft get the same bytes, with exactly two
# passages switched inline (the situation phrase, and, outside this function,
# the scaffolding's closing command) — two copies of this text would drift
# invisibly.
#
# <situation> is init | base | review: the working tree the block is written from
# (PR branch, base branch, review/* branch). <flags> is the normalised
# origin/range flag string ("--local --delta", "(defaults)"), the only home of
# that datum — config --porcelain reads it back out of the file. <delta-branch>,
# when non-empty, names the branch the range is incremental over.
#
# Two hard, measured prohibitions on the content (AGENTS.md, "Walk y
# walkthrough"): never <lower>..<tip> as ONE argument (Windows deep-cwd stat,
# "fatal: ... Filename too long", exit 128), and never
# git log/rev-list/shortlog/range-diff (a tree <lower> makes them print the whole
# repo's history, silently, exit 0). What works with either bound type:
# "git diff <lower> <tip>" as two arguments, and "git show <rev>:<path>".
walk_emit_prompt_block() {
	_wepb_tip="$1"
	_wepb_lower="$2"
	_wepb_label="$3"
	_wepb_kind="$4"
	_wepb_situation="$5"
	_wepb_flags="$6"
	_wepb_delta="${7:-}"

	printf '<!-- git-review-range: what this reading order covers, and how to see it.\n'
	printf '     This block is for whoever fills the walkthrough in (usually an agent).\n'
	printf '     It is kept when the file is rebuilt, it is never shown to the reviewer,\n'
	printf '     and it does not render on the PR. Nothing here is run for you.\n\n'

	printf '     Range under review, resolved when this skeleton was written:\n'
	printf '       tip   %s  (%s)\n' "$_wepb_tip" "$_wepb_label"
	printf '       base  %s  (%s)\n\n' "$_wepb_lower" "$_wepb_kind"

	printf '     Generated with: %s\n\n' "$_wepb_flags"

	if [ -n "$_wepb_delta" ]; then
		printf '     This is an incremental range: it covers only what was added since your\n'
		printf '     previous review of %s, not the whole PR.\n\n' "$_wepb_delta"
	fi

	# Exactly one of the three, decided by where the skeleton is being written
	# from. The review one deliberately does not promise the tree holds the whole
	# PR: in step mode it holds it only up to the cursor. It names the situation
	# and sends you to the commands, which are right in all three modes.
	case "$_wepb_situation" in
	init)
		printf '     You are standing on the PR branch: your working tree has the PR, plus\n'
		printf '     anything you have not committed. This walkthrough covers committed\n'
		printf '     history only.\n\n'
		;;
	review)
		printf '     You are inside an active review: your working tree carries PR content\n'
		printf '     plus the reviewer'\''s own edits, and how much of the PR depends on the\n'
		printf '     review mode.\n\n'
		;;
	*)
		printf '     You are standing on the base branch: the files listed below exist in\n'
		printf '     your working tree with their PRE-PR content. Reading them there gives\n'
		printf '     you the old code.\n\n'
		;;
	esac

	printf '     Write the reading order over the range above, not over what your working\n'
	printf '     tree happens to contain. Use the commands below to see the real content.\n\n'

	printf '     For any file <path> listed below:\n'
	printf '       the change the PR makes to it\n'
	printf '         git diff %s %s -- <path>\n' "$_wepb_lower" "$_wepb_tip"
	printf '       its content after the PR\n'
	printf '         git show %s:<path>\n' "$_wepb_tip"
	printf '       its content before the PR\n'
	printf '         git show %s:<path>\n' "$_wepb_lower"
	printf '       every file in the range, again\n'
	printf '         git diff --name-only %s %s\n' "$_wepb_lower" "$_wepb_tip"
	printf '     A file the PR deletes has no "after" content: git show will fail on it,\n'
	printf '     and that failure is the answer.\n'
	printf -- '-->\n'
}

# walk_prompt_block  (stdin: walkthrough content; stdout: the same, minus the block)
# Swallow the incoming instruction block so the canonical rewrite regenerates it
# instead of carrying it forward. Recognition is a prefix comparison, not a
# regex: the opening line has to START with the sentinel. Only the first block
# is consumed, and only while still in the preamble — past the first entry
# heading the text is somebody's why, never rewritten.
#
# Distinct from walk_preamble's own comment-stripping (used by the rewrite and
# by start/compare when they print the heads-up; status --why never shows the
# preamble at all, so it never goes through either). This function exists purely
# so the rewrite, with the block gone from the content, does not duplicate it.
walk_prompt_block() {
	awk '
		# The preamble ends at the first entry heading; past it, pass everything.
		!donepre && /^## / {
			line = $0
			sub(/^## /, "", line)
			if (line ~ /^([0-9]+|\?)\. /) donepre = 1
		}
		skip {
			if (index($0, "-->")) skip = 0
			next
		}
		!donepre && !seen && index($0, "<!-- git-review-range:") == 1 {
			seen = 1
			# A one-line block closes on the same line it opened.
			if (index($0, "-->") == 0) skip = 1
			next
		}
		{ print }
	'
}

# walk_is_key <tip> <path>
# True when the entry for <path> carries the reserved "> key" marker: the author
# flagging it as one of the few files that carry the change, the ones a reviewer
# must not skim. Absence is the default — the marker only means something while
# it stays selective, so it is never written on every entry.
walk_is_key() {
	walk_read "$1" | walk_body "$2" | grep -q '^> key[[:space:]]*$'
}

# walk_count_keys <tip>  (stdin: paths, one per line)
# How many of the given entries carry the "> key" marker. A count over
# walk_entry_fields' essential column rather than its own marker parsing: one
# definition of what "> key" means, and a constant number of processes for a
# reading order of any length (see the note there). Always prints a number —
# `n + 0` so an empty path list is 0, not the empty string a bare `print n`
# would give and a caller would then compare numerically under set -eu.
walk_count_keys() {
	walk_entry_fields "$1" | awk -F'\t' '$3 == "1" { n++ } END { print n + 0 }'
}

# walk_is_annotated <tip> <path>
# True when <path> has an entry in the walkthrough at <tip> — regardless of
# whether that entry's path is in range. Used to tell a guided entry apart
# from a file the reading order only carries because it changed in the review
# range (see walk_reading_order). Goes through the same two normalization
# points as every other path comparison here: walk_normalize via walk_read,
# the trim in walk_parse.
walk_is_annotated() {
	walk_read "$1" | walk_parse | cut -f2- | grep -Fxq "$2"
}

# walk_entry_fields <tip>  (stdin: paths, one per line, in order)
# Emit "position<TAB>path<TAB>essential<TAB>annotated" for each path on stdin:
# 1-based position, essential 1/0 for the "> key" marker, annotated 1/0 for
# whether the path has any walkthrough entry (0 for a file walk_reading_order
# appended because it has none). Fields only, not a porcelain line — the caller
# passes them through porcelain_row. The one place deciding those two flags:
# walk_count_keys and walk_keys_order filter this output instead of re-parsing.
#
# ONE awk for the whole list, not one per path: the loop this replaced spawned a
# walk_body awk plus two greps per entry, so a 184-entry reading order cost ~900
# processes and 27s under Git Bash on Windows (fork() emulated) — enough to blow
# the VS Code panel's 15s read timeout on every refresh.
#
# Two streams (paths, then walkthrough content) feed one awk, told apart by a
# sentinel line holding a lone tab: a path can never BE one (git quotes control
# characters unconditionally), while a why is arbitrary prose that might contain
# one. Paths go first and are buffered to END so their order survives and a
# repeated path keeps its flags.
#
# The content cannot travel as `awk -v`: -v rewrites escape sequences, and BSD awk
# refuses a -v value containing a newline outright (see walk_reading_order).
walk_entry_fields() {
	_we_content="$(walk_read "$1" || true)"
	{
		cat
		printf '\t\n'
		printf '%s\n' "$_we_content"
	} | awk '
		# Phase 1: the caller path list, up to the lone-tab sentinel.
		!tail {
			if ($0 == "\t") { tail = 1; next }
			if ($0 != "") { n++; p[n] = $0 }
			next
		}
		# Phase 2: the walkthrough. Entry headers are recognised exactly as
		# walk_body does it (numbered AND skeleton "?." entries carry a body),
		# while "annotated" follows walk_parse instead (numbered entries only,
		# empty path skipped) — the two differ on purpose and the flags must
		# keep differing the same way. A "## " heading that is not an entry
		# (## Heads-up) closes the current body, as it does there.
		/^## / {
			line = substr($0, 4)
			if (sub(/^[0-9]+\. /, "", line)) {
				sub(/[ \t]+$/, "", line)
				cur = line
				if (line != "") ann[line] = 1
			} else if (sub(/^\?\. /, "", line)) {
				sub(/[ \t]+$/, "", line)
				cur = line
			} else {
				cur = ""
			}
			next
		}
		cur != "" && /^> key[[:space:]]*$/ { key[cur] = 1 }
		END {
			for (i = 1; i <= n; i++)
				printf "%s\t%s\t%s\t%s\n", i, p[i], \
					(p[i] in key) ? 1 : 0, (p[i] in ann) ? 1 : 0
		}
	'
}

# walk_why <tip> <path>
# The "why" prose a reviewer sees for <path>: the entry body from the walkthrough
# at <tip>, with the reserved marker lines ("> key", and the "> at:" anchor of v2)
# dropped and leading/trailing blank lines trimmed.
walk_why() {
	walk_read "$1" | walk_body "$2" |
		grep -v -e '^> at: ' -e '^> key[[:space:]]*$' | awk '
		{ buf[NR] = $0 }
		END {
			s = 1; while (s <= NR && buf[s] ~ /^[ \t]*$/) s++
			e = NR; while (e >= s && buf[e] ~ /^[ \t]*$/) e--
			for (i = s; i <= e; i++) print buf[i]
		}
	'
}

# walk_sequence <tip> <lower>
# The ordered, range-filtered reading sequence for a review: parse the
# walkthrough at <tip>, keep only entries whose path is in the review range
# (changed_paths <lower> <tip>), order by the author's number, print one path
# per line. Empty output means no walkthrough or no intersecting entry —
# callers degrade to a plain whole review.
#
# Both sides feed one awk as a single stream, range first, told apart by the tab
# walk_parse puts before every entry path: git quotes control characters
# unconditionally, so a changed_paths line can never hold a literal tab. This is
# what lets it run without the scratch file it used to need, one less thing left
# behind in .git when a step fails under set -e.
walk_sequence() {
	_ws_content="$(walk_read "$1")" || return 0
	[ -n "$_ws_content" ] || return 0
	{
		# A range that will not diff (an unresolvable bound) yields no paths, so no
		# entry intersects and the caller degrades — it never aborts the review.
		changed_paths "$2" "$1" 2>/dev/null || true
		printf '%s\n' "$_ws_content" | walk_parse
	} | awk '
		{
			tab = index($0, "\t")
			if (tab == 0) { inrange[$0] = 1; next }
			ord = substr($0, 1, tab - 1) + 0
			path = substr($0, tab + 1)
			if (path in inrange) printf "%s\t%s\n", ord, path
		}
	' | LC_ALL=C sort -k1,1n | cut -f2-
}

# walk_reading_order <tip> <lower>
# The full reading order for a walk review: the guided sequence from
# walk_sequence, followed by any file range_files reports in range with no
# walkthrough entry, in git's order — including the sidecar itself when the PR
# touches it (a committed walkthrough is a file like any other; the one place
# still filtering it out is the walkthrough's own entry proposal in
# git-review-verbs/walkthrough, to avoid annotating the file you annotate in).
# Empty output means walk_sequence found no guided entry in range, and the
# caller degrades to whole: this only ever appends to a non-empty sequence,
# never turns an empty one into something walk mode would run on.
#
# Built on walk_sequence rather than duplicating its awk: one more diff, plus a
# single awk pass doing set membership over range paths (not a grep per path).
walk_reading_order() {
	_wro_seq="$(walk_sequence "$1" "$2")"
	[ -n "$_wro_seq" ] || return 0
	printf '%s\n' "$_wro_seq"
	# One awk: load guided paths into a set, emit range paths not in it (git order).
	#
	# The sequence arrives as a stream, not `awk -v`: BSD awk (what macOS ships)
	# refuses a newline inside a -v value outright ("awk: newline in string...",
	# exit 2), aborting every walk review on macOS alone — gawk and mawk accept
	# it. Same two-stream, lone-tab-sentinel shape as walk_entry_fields, safe for
	# the same reason (git quotes control characters unconditionally).
	{
		printf '%s\n' "$_wro_seq"
		printf '\t\n'
		range_files "$1" "$2"
	} | awk '
		# Phase 1: the guided sequence, up to the lone-tab sentinel.
		!tail {
			if ($0 == "\t") { tail = 1; next }
			if ($0 != "") seen[$0] = 1
			next
		}
		$0 != "" && !($0 in seen) { print }
	'
}

# walk_keys_order <tip> <lower>
# Guided walk_sequence paths that carry the reserved "> key" marker, in
# walkthrough order. Uncovered paths never appear — walk_sequence only yields
# guided entries, so filtering on essential alone is enough. A filter over
# walk_entry_fields, like walk_count_keys, for the same single-definition and
# constant-process reasons. Empty output means no essential entry intersects
# the range — callers that asked for --keys fail before opening a review rather
# than materializing an empty sequence.
walk_keys_order() {
	walk_sequence "$1" "$2" | walk_entry_fields "$1" |
		awk -F'\t' '$3 == "1" { print $2 }'
}

# emit_reading_offers <branch> <remote> <source_mode> <delta>
# Print offer rows for config --porcelain. source_mode is remote|local|offline;
# delta is 0|1. Never fetches. Dies on unresolvable tip or on --delta without a
# marker for that origin. Lower bound mirrors start (merge-base / previous tip +
# fold_lower) without creating a review branch.
emit_reading_offers() {
	_ero_branch="$1"
	_ero_remote="$2"
	_ero_source="$3"
	_ero_delta="$4"

	_ero_base="$(git config reviewworkflow.base || true)"
	_ero_offline=0
	_ero_local=0
	case "$_ero_source" in
	offline) _ero_offline=1; _ero_local=1 ;;
	local) _ero_local=1 ;;
	remote) ;;
	*)
		echo "error: internal: unknown offer source $_ero_source" >&2
		return 1
		;;
	esac

	if [ "$_ero_local" -eq 1 ]; then
		_ero_srcref="refs/heads/$_ero_branch"
		_ero_srclabel="$_ero_branch"
		_ero_markerkey="reviewworkflowlocal.$_ero_branch.reviewed"
	else
		_ero_srcref="refs/remotes/$_ero_remote/$_ero_branch"
		_ero_srclabel="$_ero_remote/$_ero_branch"
		_ero_markerkey="reviewworkflow.$_ero_branch.reviewed"
	fi

	# Tip missing is a hard error for every origin (remote default, local,
	# offline, delta): silently returning zero offer rows would look to a client
	# like an older CLI lacking this feature, triggering its whole+step
	# fallback, instead of reporting "no remote tip". Local-only branches must
	# use --local.
	if ! git rev-parse --verify --quiet "$_ero_srcref^{commit}" >/dev/null; then
		echo "error: $_ero_srclabel not found" >&2
		return 1
	fi
	_ero_tip="$(git rev-parse "$_ero_srcref")"

	_ero_baseref=""
	if [ -n "$_ero_base" ]; then
		if [ "$_ero_offline" -eq 1 ]; then
			if git rev-parse --verify --quiet "refs/heads/$_ero_base^{commit}" >/dev/null; then
				_ero_baseref="refs/heads/$_ero_base"
			fi
		else
			if git rev-parse --verify --quiet "refs/remotes/$_ero_remote/$_ero_base^{commit}" >/dev/null; then
				_ero_baseref="refs/remotes/$_ero_remote/$_ero_base"
			fi
		fi
		if [ -z "$_ero_baseref" ]; then
			_ero_bcommit="$(git rev-parse --verify --quiet "$_ero_base^{commit}" || true)"
			if [ -n "$_ero_bcommit" ]; then
				_ero_baseref="$_ero_bcommit"
			fi
		fi
	fi

	_ero_prev="$(git config "$_ero_markerkey" || true)"
	if [ "$_ero_delta" -eq 1 ]; then
		[ -n "$_ero_prev" ] || {
			echo "error: no previous review of $_ero_branch recorded for this origin; run a full review first" >&2
			return 1
		}
		[ "$_ero_prev" != "$_ero_tip" ] || {
			echo "error: no new commits since your last review of $_ero_branch" >&2
			return 1
		}
		git merge-base --is-ancestor "$_ero_prev" "$_ero_tip" || {
			echo "error: $_ero_branch was force-pushed since your last review; run a full review instead" >&2
			return 1
		}
		_ero_start="$_ero_prev"
	else
		# Full range needs a base; without it, skip offers (delta rows may still
		# have been emitted above by the caller). Not a hard error: config
		# porcelain is also used only for candidates/deltas before base is set.
		if [ -z "$_ero_base" ] || [ -z "$_ero_baseref" ]; then
			return 0
		fi
		_ero_start="$(git merge-base "$_ero_baseref" "$_ero_srcref")" || return 0
		[ "$_ero_start" != "$_ero_tip" ] || return 0
	fi

	# Tree-only lower bound: offers must not commit-tree dangling "review lower
	# bound" objects into the DB on every porcelain probe.
	_ero_lower="$(resolve_lower_bound "$_ero_start" "$_ero_baseref" "$_ero_tip")"

	# The reviewer's own draft counts as the walkthrough in force here too, so
	# the offers describe the review that start would actually create.
	walk_use_draft "$_ero_branch"

	_ero_walk=0
	if wtcontent="$(walk_read "$_ero_tip")" && [ -n "$wtcontent" ]; then
		_ero_guided="$(walk_sequence "$_ero_tip" "$_ero_lower")"
		_ero_n="$(printf '%s\n' "$_ero_guided" | grep -c . || true)"
		if [ "$_ero_n" -ge 1 ]; then
			_ero_walk=1
		fi
	fi

	if [ "$_ero_walk" -eq 1 ]; then
		porcelain_row offer walk recommended
		_ero_keys="$(walk_keys_order "$_ero_tip" "$_ero_lower")"
		_ero_kn="$(printf '%s\n' "$_ero_keys" | grep -c . || true)"
		if [ "$_ero_kn" -ge 1 ]; then
			porcelain_row offer keys available
		fi
	fi
	# Drafting the reading order yourself is a reading offer of its own, and
	# exactly one of the three. Never `draft` on top of a usable walkthrough:
	# replacing the author's order is a deliberate, terminal-only act. The other
	# two ARE offered alongside walk, since walk IS the reviewer's own draft
	# there.
	#
	# draft-update vs draft-resume is decided HERE and not by the client: it
	# needs both tips, which the draft's <state> cannot answer -- that field
	# asks "has this order been read?", not "does it still cover the range?",
	# so a branch that moved after review still reports `reviewed`. Guessed
	# client-side, it offered to reconcile a range that had not moved: a no-op
	# landing the reviewer on a `reviewed` row with no button that does
	# anything.
	#
	#   drifted     the block records a different tip -- entries are missing or
	#               gone, something to reconcile.
	#   up to date  and still being written: finishing it is the next move.
	#   up to date  and complete: nothing to offer -- `walk` above already
	#               reads it, and starting over is a decision of its own.
	#
	# The first question is ZERO processes (a builtin read of the block
	# walk_use_draft already located); the count only runs once it answers
	# "up to date", and never at all without a branch argument.
	if walk_has_draft_file "$_ero_branch"; then
		_ero_dpath="$(walk_draft_path "$_ero_branch")"
		_ero_dtip="$(walk_sidecar_block_tip "$_ero_dpath" || true)"
		if [ -n "$_ero_dtip" ] && [ "$_ero_dtip" != "$_ero_tip" ]; then
			porcelain_row offer draft-update available
		elif [ "$_ero_walk" -eq 0 ] || ! walk_draft_filled "$_ero_dpath"; then
			# _ero_walk == 0 is the safety net, not a nicety: a complete draft
			# whose paths no longer meet the range leaves walk unoffered, and
			# silence here would be a reading order with no way to reach it.
			porcelain_row offer draft-resume available
		fi
	elif [ "$_ero_walk" -eq 0 ]; then
		porcelain_row offer draft available
	fi
	porcelain_row offer step available
	porcelain_row offer whole available
	return 0
}

# walk_at_base
# True when HEAD still sits where start pinned it, false when it moved, and
# non-zero-with-no-answer when the review predates the key that records it.
#
# Walk mode keeps HEAD at the review's lower bound for the review's whole life,
# so this is a question git can answer outright instead of inferring it from
# the reading sequence having shrunk — the old approach, which broke once a
# reviewer's draft became editable: shrinking now has two causes, and the
# inference picked the wrong one (telling a reviewer who had only edited their
# own draft to run git reset --soft).
#
# Three states, not two: a review created before reviewwalkbase existed has no
# recorded base, and guessing would repeat the same mistake in reverse — callers
# fall back to the old inference there.
walk_at_base() {
	_wab_base="$(git config "branch.$cur.reviewwalkbase" || true)"
	[ -n "$_wab_base" ] || return 2
	[ "$(git rev-parse HEAD)" = "$_wab_base" ]
}

# walk_recover_cursor
# Re-seat a cursor that the reviewer's own draft got shorter under, or fail (and
# leave walk_range_error to explain). True only when the cursor ran off the end
# (never off the front, which no edit can cause), entries remain, HEAD is
# provably still at the base, and the walkthrough in force is a still-existing
# draft.
#
# Clamps rather than errors because those conditions together mean the state is
# intact and only the reading position went stale — and the position is not
# precious, since the sequence is re-derived every command. The alternative was a
# dead end: every verb loads this metadata first, so an out-of-range cursor made
# next/prev/status all abort alike, leaving `git review abort` as the only way out
# of having edited your own prose.
#
# reviewwalkcount moves with it: it is the baseline a later genuine range change
# is measured against, so leaving it stale would re-report this same shrink for
# the rest of the review.
walk_recover_cursor() {
	[ "$walkstep" -gt "$total" ] || return 1
	[ "$total" -ge 1 ] || return 1
	walk_at_base || return 1
	# walk_draft_src, not the reviewwalkfromdraft flag: the flag is only raised
	# when start/compare open ON a draft, but this function exists for a draft
	# written MID-review, which by definition never had one — reading the flag
	# here made recovery unreachable on its own motivating path.
	_wrc_draft="${walk_draft_src:-}"
	[ -n "$_wrc_draft" ] || return 1
	walk_is_draft "$_wrc_draft" || return 1

	echo "note: your walkthrough draft for $_wrc_draft now has $total $(entry_noun "$total") in this review's range; the cursor was at $walkstep and moved to $total." >&2
	# Best-effort: this is the one place the read path writes config, so it also
	# runs from `git review status` on every panel refresh. A write can fail for
	# reasons unrelated to the review (.git/config.lock held by another process,
	# a read-only gitdir) and none of that is worth killing the command over —
	# the clamp is already in force for this call, and the next one retries.
	#
	# Not redundant with the caller's AND-OR list: that only suppresses -e today
	# because of an invariant living in another function, one refactor away from
	# turning a lost lock into an aborted status.
	git config "branch.$cur.reviewwalkstep" "$total" || true
	git config "branch.$cur.reviewwalkcount" "$total" || true
	walkstep="$total"
	walkcount="$total"
	return 0
}

# walk_range_error <walkstep> <total> <walkcount>
# Emit the right diagnostic for a walk cursor that fell outside the live reading
# range, then exit 1. A walk review's tip and committed walkthrough are frozen,
# so the derived sequence only shrinks when HEAD moves off the base — almost
# always a stray `git commit` folding the staged whole-PR diff into HEAD. When
# live <total> dropped below the <walkcount> recorded at start, name that
# recoverable cause and its fix instead of blaming "corrupt metadata"; a range
# that is still intact (total == walkcount, or walkcount unusable) IS
# corruption — a hand-edited key — and keeps the original diagnostic.
#
# The reviewer's draft adds two more recoverable causes, each with its own
# message: the draft is gone (deleted or emptied), or it contributes no entry to
# this range. Both are states of a file the reviewer owns and can fix, so both
# name the fix. "Corrupt metadata" is the last resort, not the catch-all.
walk_range_error() {
	_wre_step="$1"
	_wre_total="$2"
	_wre_count="$3"
	case "$_wre_count" in
	'' | *[!0-9]*) _wre_count=0 ;;
	esac
	# A reviewer's draft, unlike a committed walkthrough, can be deleted out from
	# under a live review, changing the sequence's shape exactly as a stray
	# commit does — without this the reviewer was told HEAD moved and to run
	# git reset --soft, which is both wrong and destructive-sounding.
	#
	# Decided on reviewwalkfromdraft (recorded at creation), not on "no
	# walkthrough left": when the PR has its own, deleting the draft falls back
	# to the author's order, so walk_read still succeeds while the range has
	# still collapsed — exactly the case that got the HEAD message wrong. A
	# flag, not the name, because whether a draft WAS being read cannot be
	# recomputed once the file is gone; the name is recorded separately
	# (walk_review_draft_src). The old total==0 test stays as fallback for
	# reviews started before the flag.
	_wre_draft=""
	if [ "$(git config "branch.$cur.reviewwalkfromdraft" || true)" = "1" ]; then
		_wre_draft="${walk_draft_src:-$src}"
	elif [ -n "${walk_draft_src:-}" ] && walk_is_draft "$walk_draft_src"; then
		# A draft written mid-review carries no flag (nothing to record at
		# creation), so it is adopted from the loader's context instead, but only
		# once walk_is_draft confirms one is actually in force — walk_draft_src
		# falls back to the review's own source name, so taking it
		# unconditionally would make every draft-less review look like one
		# whose draft went missing, misdiagnosing a stray commit as "your draft
		# is gone".
		_wre_draft="$walk_draft_src"
	fi
	_wre_gone=0
	if [ -n "$_wre_draft" ]; then
		if ! walk_is_draft "$_wre_draft"; then
			_wre_gone=1
		fi
	elif [ "$_wre_total" -eq 0 ] && ! walk_read "$tip" >/dev/null 2>&1; then
		_wre_draft="$src"
		_wre_gone=1
	fi
	if [ "$_wre_gone" -eq 1 ]; then
		# Deleted and emptied are the same to walk_read but different to the
		# reviewer, who likely has the file open — told apart here with
		# walk_has_draft_file (custody), since walk_is_draft just answered the
		# other question. It also picks the fix: the draft verb refuses to
		# overwrite an existing file, so an empty draft needs --force or the
		# reviewer hits a second error.
		if walk_has_draft_file "$_wre_draft"; then
			_wre_what="the file is now empty"
			_wre_fix="git review walkthrough draft --force $_wre_draft"
		else
			_wre_what="the file no longer exists"
			_wre_fix="git review walkthrough draft $_wre_draft"
		fi
		echo "error: the walkthrough this review was reading is gone — it was $_wre_draft's draft, and $_wre_what. Write it again with '$_wre_fix', or discard the review with 'git review abort'." >&2
		exit 1
	fi
	# The shrink only points to a stray commit while nothing else could have
	# caused it: if the base is recorded and HEAD is still on it, this message
	# would be provably false, so it is skipped in favor of the generic
	# diagnostic below. walk_recover_cursor already handles the one recoverable
	# shape of that (their own draft, still there, cursor past the end).
	if [ "$_wre_step" -ge 1 ] && [ "$_wre_count" -ge 1 ] && [ "$_wre_total" -lt "$_wre_count" ] &&
		! walk_at_base; then
		echo "error: HEAD has moved off this review's base — the walkthrough cursor is at entry $_wre_step but only $_wre_total of $_wre_count $(entry_noun "$_wre_count") remain in range. Walk mode keeps the whole-PR diff staged with HEAD at the base; you now have commit(s) on top (did you run git commit?). Undo them with 'git reset --soft' to restage the diff, or 'git review abort' to discard the review, then retry." >&2
		exit 3
	fi
	# A draft that is in force but yields no entry in range — a state of the
	# draft, not corruption: the reviewer rewrote it down to the skeleton
	# ("## ?." headings are not entries until numbered) or wrote paths outside
	# the range. walk_recover_cursor cannot clamp it (nothing to clamp to), and
	# without this branch the reviewer who follows the "gone" message above and
	# drafts the skeleton is wrongly told "corrupt metadata".
	#
	# Deliberately below the HEAD check: a stray commit also empties the
	# sequence, and that state is about HEAD, not the draft — ordering this
	# first would misdirect a reviewer who just committed, and change the exit
	# code clients read as out-of-range from 3 to 1.
	if [ -n "$_wre_draft" ] && [ "$_wre_total" -eq 0 ]; then
		echo "error: your walkthrough draft for $_wre_draft has no entries in this review's range; the cursor is at entry $_wre_step. Number the entries and run 'git review walkthrough draft --build $_wre_draft', or discard the review with 'git review abort'." >&2
		exit 1
	fi
	echo "error: review entry $_wre_step out of range (1..$_wre_total) — corrupt metadata? Discard the review with 'git review abort'." >&2
	exit 1
}

# load_walk_review_meta
# Confirm HEAD is on a review/* branch in walk mode and load its metadata into the
# globals the caller and goto_walk_entry rely on: cur, src, tip, walkstep,
# walkcount, walkpaths and total. The sequence is re-derived (not persisted), the
# way the step commands re-derive commits with rev-list; HEAD is pinned at the
# lower bound for a walk review's life, so the derivation is stable across edits.
# Exits with a diagnostic on any inconsistency.
load_walk_review_meta() {
	cur="$(git symbolic-ref --quiet --short HEAD || true)"
	[ -n "$cur" ] || {
		echo "error: not on a branch" >&2
		exit 1
	}
	case "$cur" in
	review/*) ;;
	*)
		echo "error: not on a review/* branch (HEAD is $cur)" >&2
		exit 2
		;;
	esac

	mode="$(git config "branch.$cur.reviewmode" || true)"
	[ "$mode" = "walk" ] || {
		echo "error: $cur was not started with a walkthrough" >&2
		exit 1
	}

	src="$(git config "branch.$cur.reviewsource" || true)"
	tip="$(git config "branch.$cur.reviewtip" || true)"
	walkstep="$(git config "branch.$cur.reviewwalkstep" || true)"
	walkcount="$(git config "branch.$cur.reviewwalkcount" || true)"

	if [ -z "$src" ] || [ -z "$tip" ]; then
		if [ -z "$src" ]; then
			echo "error: missing review metadata; was $cur created with git review start? Switch away, then delete it with 'git branch -D $cur'." >&2
		else
			echo "error: missing review metadata; was $cur created with git review start? Discard the review with 'git review abort'." >&2
		fi
		exit 1
	fi

	# Point the readers at the draft this review is reading, if any, before the
	# sequence below (the first thing here to go through walk_read). Doing it
	# in the context loader, not in each verb, guarantees every surface of one
	# review — next, prev, status --why, preview — reads the same walkthrough.
	# Resolved via walk_review_draft_src, which answers "under what name?" from
	# what the review recorded (see that function for why this can differ from
	# reviewsource).
	walk_use_draft "$(walk_review_draft_src "$cur")"

	# Keys-only submode (start/compare --keys): sequence is guided ∩ keys, not
	# the full reading order. The flag lives on the branch; absence is full walk.
	if [ "$(git config "branch.$cur.reviewwalkkeys" || true)" = "1" ]; then
		walkpaths="$(walk_keys_order "$tip" "$(git rev-parse HEAD)")"
	else
		walkpaths="$(walk_reading_order "$tip" "$(git rev-parse HEAD)")"
	fi
	# grep -c returns 1 (aborting under set -e in POSIX sh) when walkpaths is empty;
	# guard it so a lost sequence reaches the range check below as total=0.
	total="$(printf '%s\n' "$walkpaths" | grep -c . || true)"

	case "$walkcount" in
	'' | *[!0-9]*)
		echo "error: corrupt review metadata: reviewwalkcount is '$walkcount', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
		;;
	esac
	[ "$walkcount" -ge 1 ] || {
		echo "error: corrupt review metadata: reviewwalkcount is '$walkcount', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
	}
	case "$walkstep" in
	'' | *[!0-9]*)
		echo "error: corrupt review metadata: reviewwalkstep is '$walkstep', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
		;;
	esac
	if [ "$walkstep" -lt 1 ] || [ "$walkstep" -gt "$total" ]; then
		# Recovery before diagnosis: the one cause that leaves the review intact is
		# the reviewer editing their own draft, and that one is repaired rather than
		# reported. Everything else still gets the message it earned.
		walk_recover_cursor || walk_range_error "$walkstep" "$total" "$walkcount"
	fi
}

# show_walk_entry <k>
# Print the k-th entry of the reading order: a rule, the "[k/N] <path>" header,
# either the author's "why" prose or a fixed line for a file the walkthrough
# does not annotate, another rule and the prompt. A "> key" entry is labelled
# as such (the order says what to read when, the marker says which not to
# skim); an unannotated one is labelled "(uncovered)" instead. No line number
# in the path on purpose: it would just open the file at the top in an IDE
# terminal anyway, and a hunk line goes stale the moment you edit.
# Relies on the globals load_walk_review_meta sets (tip, total, walkpaths).
show_walk_entry() {
	_swe_path="$(printf '%s\n' "$walkpaths" | sed -n "${1}p")"
	if walk_is_annotated "$tip" "$_swe_path"; then
		_swe_mark=""
		if walk_is_key "$tip" "$_swe_path"; then
			_swe_mark="  (key)"
		fi
		_swe_body="$(walk_why "$tip" "$_swe_path")"
	else
		_swe_mark="  (uncovered)"
		_swe_body="this file changes in the review and the walkthrough does not annotate it"
	fi
	printf -- '----\n[%s/%s] %s%s\n%s\n----\nread this file, edit if needed, then run git review next\n' \
		"$1" "$total" "$_swe_path" "$_swe_mark" "$_swe_body"
}

# goto_walk_entry <k>
# Move the walk cursor to entry <k> and show it. Unlike goto_step this touches
# nothing but the cursor key: walk never stages or resets, so working tree and
# index are left exactly as they were.
goto_walk_entry() {
	git config "branch.$cur.reviewwalkstep" "$1"
	walkstep="$1"
	show_walk_entry "$1"
}

# ── Authoring guides ──────────────────────────────────────────────────────────
#
# A guide is prose about CONTENT: which entries deserve "> key", how to write a
# why, what belongs in the heads-up — team's (.review/walkthrough-guide.md,
# committed) and your own (<git-common-dir>/review-walkthrough-guide.md,
# outside the work tree, never staged/committed/swept into review-fixes/); see
# AGENTS.md's prose-files table. Both apply when both are in force, and the
# skeleton says which wins on a contradiction: yours, same precedence walk_read
# applies between draft and sidecar.
#
# Neither is read, parsed or validated by this suite — detected and named only;
# the agent filling the walkthrough in reads them. Keeps build the only owner
# of the format, with no validation to drift.
#
# The own guide lives PLAIN, never inside review-walkthrough/: walk_draft_list
# recurses that directory taking every *.md as a <src> branch name, so a guide
# filed there would surface as a phantom draft everywhere that enumerates them.

# guide_paths_init
# Resolve both guide paths once per process into _guide_team_path/_guide_own_path,
# both absolute and in the SAME path style, in ONE git process (rev-parse answers
# both in a single call). Same "assign in the caller's own shell" rule as
# walk_gitdir_init, for the same reason: a cache written inside a "$(...)" dies
# with its subshell.
#
# The reviewer's guide belongs to the COMMON gitdir, never the worktree one: a
# linked worktree has its own gitdir but shares the common one, and a guide is
# a property of the repository, not of the worktree you happen to be in.
#
# Derived from --absolute-git-dir and a string-strip of "/worktrees/<name>",
# rather than --git-common-dir: that answers relative to the CURRENT DIRECTORY,
# and on Windows the obvious fix (prefixing $PWD) mixes path styles inside one
# porcelain record -- rev-parse hands back "C:/Users/...", Git Bash's $PWD
# hands back "/tmp/...", and a client given the second cannot open the file.
# (--path-format=absolute would be the direct route; it needs git 2.31, this
# project supports 2.23.)
#
# A bare repository has no work tree and therefore no team guide at all: both
# paths stay empty and every caller treats that as nothing to report.
guide_paths_init() {
	[ -z "${_guide_paths_done:-}" ] || return 0
	_guide_paths_done=1
	_guide_team_path=""
	_guide_own_path=""
	_gpi_top=""
	_gpi_gitdir=""
	_gpi_n=0
	while IFS= read -r _gpi_line; do
		_gpi_n=$((_gpi_n + 1))
		case "$_gpi_n" in
		1) _gpi_top="$_gpi_line" ;;
		2) _gpi_gitdir="$_gpi_line" ;;
		esac
	done <<EOF
$(git rev-parse --show-toplevel --absolute-git-dir 2>/dev/null || true)
EOF
	[ "$_gpi_n" -eq 2 ] || return 0
	[ -n "$_gpi_top" ] && [ -n "$_gpi_gitdir" ] || return 0
	# Shortest suffix, so a repository whose own path contains "/worktrees/" keeps
	# the last occurrence -- the one git just appended -- and not an earlier one.
	case "$_gpi_gitdir" in
	*/worktrees/*) _gpi_common="${_gpi_gitdir%/worktrees/*}" ;;
	*) _gpi_common="$_gpi_gitdir" ;;
	esac
	_guide_team_path="$_gpi_top/.review/walkthrough-guide.md"
	_guide_own_path="$_gpi_common/review-walkthrough-guide.md"
}

# guide_in_force <path>
# Whether <path> is a guide with something in it. Same rule and reason as
# walk_draft_body: empty or whitespace-only is not a set of conventions, and
# lets "git review walkthrough guide" create the file empty without yet
# claiming one exists.
#
# ZERO processes, unlike walk_draft_body: the question is only "is there a
# non-blank line", answered by a builtin read loop that stops at the first one
# — line 1 for a real guide. config --porcelain runs on every panel refresh, so
# that is free vs not.
#
# Does not catch a file holding only a UTF-8 BOM (reads as non-whitespace):
# deliberate, since recognising it needs a printf for one line's cost in a
# skeleton.
guide_in_force() {
	[ -n "$1" ] || return 1
	[ -f "$1" ] || return 1
	[ -s "$1" ] || return 1
	_gif_line=""
	while IFS= read -r _gif_line || [ -n "$_gif_line" ]; do
		case "$_gif_line" in
		*[![:space:]]*) return 0 ;;
		esac
		_gif_line=""
	done <"$1"
	return 1
}

# guide_state_of <path>
# Set _guide_state to in-force | empty | absent — the three states
# config --porcelain reports, and the three a client needs to decide between
# offering Open, Create or Discard.
#
# "empty" is not folded into "absent" even though both mean "no conventions in
# play": the file is there, so the offer is to open and fill it, not to create
# it, and discarding it is possible where discarding a missing file is not.
#
# Sets a variable instead of printing, so a caller pays no fork to ask.
guide_state_of() {
	if guide_in_force "$1"; then
		_guide_state=in-force
	elif [ -n "$1" ] && [ -f "$1" ]; then
		_guide_state=empty
	else
		_guide_state=absent
	fi
}

# emit_guide_records
# One "guide<TAB>kind<TAB>path<TAB>state" row per guide, ALWAYS BOTH, team first.
#
# Both rows always, unlike the draft records, which exist only for drafts that
# exist: a client cannot offer to CREATE a guide it was never told about, and
# rebuilding the path on its side is the thing the reported-path rule exists to
# prevent. So absence is reported, not implied by silence.
#
# Cost on the panel's refresh path: the one rev-parse in guide_paths_init, and
# nothing else. The state of each guide is file tests plus, for a guide that has
# bytes in it, a builtin read that stops at its first non-blank line.
emit_guide_records() {
	guide_paths_init
	[ -n "$_guide_team_path" ] || return 0
	guide_state_of "$_guide_team_path"
	porcelain_row guide team "$_guide_team_path" "$_guide_state"
	guide_state_of "$_guide_own_path"
	porcelain_row guide own "$_guide_own_path" "$_guide_state"
}

# ── The author's own walkthrough ───────────────────────────────────────────────
#
# A committed walkthrough is written once when the PR is finished, then the PR
# keeps moving -- review comments land, files change -- and nothing says the
# reading order stopped matching except build, which you have to remember to
# run at the one moment nobody is thinking about the walkthrough.
#
# So the panel says it instead, off one porcelain row on a refresh path that
# must stay cheap: what follows answers "is it worth looking?", deliberately
# not the exact question, which is build's to answer.

# walk_sidecar_block_tip <path>
# The tip SHA recorded in the instruction block of <path>, or nothing.
#
# The block names the range the file was last written or validated against, which
# is precisely the datum "has this gone stale?" needs, and it is already there --
# every init and every build regenerates it (walk_emit_prompt_block).
#
# ZERO processes, like guide_in_force and for the same reason: this runs on every
# panel refresh. A builtin read loop, stopping at the block's own end, at the
# first entry heading, or at a line cap for a file whose block was deleted by
# hand -- which is legal, and which leaves the state unknown rather than wrong.
#
# IFS=' ' does the trimming: the block writes the line indented and
# space-padded ("       tip   <sha>  (HEAD)"), and read's own field splitting
# collapses all of it.
walk_sidecar_block_tip() {
	_wsbt_n=0
	while IFS=' ' read -r _wsbt_k _wsbt_v _wsbt_rest || [ -n "$_wsbt_k" ]; do
		_wsbt_n=$((_wsbt_n + 1))
		case "$_wsbt_k" in
		tip)
			# Validated here rather than trusted: the value is about to be handed
			# to git as a revision, and a "tip" that is somebody's prose must not
			# become a git argument. 40 hex characters, no more, no less.
			case "$_wsbt_v" in
			*[!0-9a-f]* | '') ;;
			????????????????????????????????????????)
				printf '%s' "$_wsbt_v"
				return 0
				;;
			esac
			;;
		esac
		case "$_wsbt_k" in
		'##') return 1 ;;
		esac
		case "$_wsbt_rest$_wsbt_v$_wsbt_k" in
		*'-->'*) return 1 ;;
		esac
		[ "$_wsbt_n" -lt 80 ] || return 1
		_wsbt_k=""
	done <"$1"
	return 1
}

# walk_draft_filled <path>
# True when <path> declares at least one unit and every one of them is written:
# the same annotated >= total > 0 that the three panels call `filled`, asked of a
# single draft.
#
# One awk, and only on the branch the start assistant is asking about -- never in
# the pathless refresh, which is why this is a helper of its own rather than a
# field of the draft records. The caller reaches it only after the cheap question
# (has the range moved?) has already been answered with zero processes, so the
# common paths -- no draft, or a draft to reconcile -- never pay for it.
walk_draft_filled() {
	_wdf_row="$(walk_draft_progress "$1")"
	_wdf_ann="$(printf '%s' "$_wdf_row" | cut -f2)"
	_wdf_tot="$(printf '%s' "$_wdf_row" | cut -f3)"
	[ -n "$_wdf_tot" ] || return 1
	[ "$_wdf_tot" -gt 0 ] || return 1
	[ "$_wdf_ann" -ge "$_wdf_tot" ] || return 1
	return 0
}

# walk_sidecar_superseded <tip> <baseref>
# True when a walkthrough written against <tip> belongs to a PR ALREADY
# integrated into <baseref> -- not this PR's reading order at all.
#
# The case: your PR merges, its sidecar travels into the base, you branch again
# and touch one of the same files -- its entry is still there, with a why
# describing a change that already shipped. Reconciling against it keeps prose
# that belongs to somebody else's range and would ride out on the next commit;
# it is not "stale", nothing about it fell behind.
#
# One process: a tip that is an ancestor of the base is a tip whose commits are
# in the base. Bound is the base, not the merge-base, on purpose -- the
# question is "did this land?", and the merge-base moves with every rebase.
#
# Returns 2, not 1, when the answer cannot be had (no tip recorded, an object
# this clone lacks): callers must not read "no" out of "cannot tell", or a
# fresh clone would silently reconcile against an already-merged PR.
walk_sidecar_superseded() {
	[ -n "$1" ] || return 2
	[ -n "$2" ] || return 2
	git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1 || return 2
	git merge-base --is-ancestor "$1" "$2" 2>/dev/null
}

# emit_walkthrough_record [<base>] [<remote>]
# The author's sidecar as one row:
#   walkthrough<TAB><state><TAB><path><TAB><annotated><TAB><total>[<TAB><branch>]
#
# <branch> is the branch this walkthrough annotates (the one HEAD sits on,
# which init/build resolve too), letting clients say "Walkthrough" once instead
# of three times. Omitted, never blank, when HEAD is detached: the row still
# emits, only its name has no answer.
#
# state is absent | in-sync | stale | superseded | unknown, emitted in all five
# cases -- like emit_guide_records' two guides, and unlike the draft records: a
# client cannot offer to create a walkthrough it was never told about.
#
#   absent      no .review/walkthrough.md in the work tree
#   in-sync     the range has not changed outside .review/ since last written/built
#   stale       it has -- files entered/left the range, or an annotated file
#               moved on. Worth looking at, not a verdict.
#   superseded  the walkthrough of a PR already merged into the base -- it
#               travelled in with the merge, describing a shipped change
#   unknown     no instruction block (legal to delete by hand), or its tip is an
#               object this clone no longer has (force-push, fresh clone)
#
# `superseded` is asked only once the diff already said `stale` (a walkthrough
# still matching its range cannot be another PR's), keeping its two extra
# processes off the common path.
#
# The comparison EXCLUDES .review/: without it, committing the walkthrough itself
# (which moves HEAD) made the ordinary init/build/commit flow end on a panel
# calling the file just written already out of date.
#
# Cost when the file is there: nothing per entry and nothing for the branch name
# -- one builtin block read, one git diff, and the progress awk.
emit_walkthrough_record() {
	_ewr_base="${1:-}"
	_ewr_remote="${2:-origin}"
	guide_paths_init
	[ -n "$_guide_team_path" ] || return 0
	_ewr_path="${_guide_team_path%/walkthrough-guide.md}/walkthrough.md"

	current_branch_init
	if [ ! -f "$_ewr_path" ]; then
		emit_walkthrough_row absent "$_ewr_path" 0 0
		return 0
	fi

	_ewr_state=unknown
	_ewr_tip="$(walk_sidecar_block_tip "$_ewr_path" || true)"
	if [ -n "$_ewr_tip" ]; then
		# Two revisions as two arguments, never "A..B" (see walk_emit_prompt_block
		# / AGENTS.md "Walk y walkthrough" for the Windows deep-cwd trap avoided).
		#
		# The pathspec excludes the sidecar and the guide. :(exclude) is git
		# 2.13; this project's floor is 2.23.
		_ewr_rc=0
		git diff --quiet "$_ewr_tip" HEAD -- . ':(exclude).review' 2>/dev/null ||
			_ewr_rc=$?
		case "$_ewr_rc" in
		0) _ewr_state=in-sync ;;
		1) _ewr_state=stale ;;
		esac
		# Only over a stale answer, and only with a base to ask about -- see the
		# state table above for why.
		if [ "$_ewr_state" = stale ] && [ -n "$_ewr_base" ]; then
			_ewr_baseref=""
			if git rev-parse --verify --quiet \
				"refs/remotes/$_ewr_remote/$_ewr_base^{commit}" >/dev/null 2>&1; then
				_ewr_baseref="refs/remotes/$_ewr_remote/$_ewr_base"
			elif git rev-parse --verify --quiet \
				"refs/heads/$_ewr_base^{commit}" >/dev/null 2>&1; then
				_ewr_baseref="refs/heads/$_ewr_base"
			fi
			if [ -n "$_ewr_baseref" ] &&
				walk_sidecar_superseded "$_ewr_tip" "$_ewr_baseref"; then
				_ewr_state=superseded
			fi
		fi
	fi

	# The same pair the drafts report, from the same awk, so "how much of it is
	# written" means one thing across both sides of the review.
	_ewr_ann=0
	_ewr_tot=0
	while IFS="$(printf '\t')" read -r _ewr_f _ewr_a _ewr_t _ewr_rest; do
		[ -n "$_ewr_f" ] || continue
		_ewr_ann="$_ewr_a"
		_ewr_tot="$_ewr_t"
	done <<EOF
$(walk_draft_progress "$_ewr_path")
EOF
	emit_walkthrough_row "$_ewr_state" "$_ewr_path" "$_ewr_ann" "$_ewr_tot"
}

# emit_walkthrough_row <state> <path> <annotated> <total>
# The single place the walkthrough row is written, so that the two callers above
# cannot disagree about the trailing branch field -- omitted, never blank, when
# HEAD is detached (contracts/config-porcelain.md: omit, never blank, never a
# sentinel). Requires current_branch_init to have run.
emit_walkthrough_row() {
	if [ -n "${_cur_branch:-}" ]; then
		porcelain_row walkthrough "$1" "$2" "$3" "$4" "$_cur_branch"
	else
		porcelain_row walkthrough "$1" "$2" "$3" "$4"
	fi
}
