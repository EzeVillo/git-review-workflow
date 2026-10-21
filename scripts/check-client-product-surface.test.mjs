import {readFileSync} from "node:fs";
import {test} from "node:test";
import assert from "node:assert/strict";
import {validateCommentsSurface,validateCommentReveal} from "./comments-surface.mjs";
const yaml=readFileSync(new URL("../contracts/client-product-surface.yaml",import.meta.url),"utf8").replace(/\r\n/g,"\n");
test("comments canonical is complete",()=>assert.deepEqual(validateCommentsSurface(yaml),[]));
test("conditional reveal rejects missing gate condition and unconditional calls",()=>{
    const gate='if (id === "addComment" && !commentsBlockBorn) return;';
    const caller='if (!error && born) revealPanel("addComment", reveal, true);';
    assert.deepEqual(validateCommentReveal(gate,caller),[]);
    assert.ok(validateCommentReveal(gate.replace('!commentsBlockBorn','false'),caller).length>0);
    assert.ok(validateCommentReveal(gate,caller.replace(' && born','')).length>0);
    assert.ok(validateCommentReveal(gate,'').length>0);
});
for(const [name,from,to] of [
    ["general comment diff hidden", "open_diff_scope: [selection, file]", "open_diff_scope: [selection, file, general]"],
    ["individual deletion preserves other entries", "delete_entry: preserve_other_entries_and_numbers", "delete_entry: renumber_all"],
    ["individual deletion keeps browser", "after_delete: select_next_or_previous_keep_browser_open", "after_delete: close"],
    ["individual deletion confirms", "deleteCommentEntry: {label: \"Delete\", emphasis: secondary, confirms: true", "deleteCommentEntry: {label: \"Delete\", emphasis: secondary, confirms: false"],
    ["exact selection endpoints",'selection_coordinates: utf16_1based_end_exclusive','selection_coordinates: whole_lines'],
    ["selection scope label",'selection_label: "Selected code"','selection_label: "Selected lines"'],
    ["comment body label",'body_label: "Comment"','body_label: ""'],
    ["context effect on shared",'context_shared_note: "Shared comments come from this branch in either case."','context_shared_note: ""'],
    ["Local-only context explanation",'context_local_note: "Choose whether to restore previous Local notes."','context_local_note: ""'],
    ["new review keeps previous notes",'new_context_detail: "Keep previous Local notes separate."','new_context_detail: ""'],
    ["continuation restores private notes",'continue_context_detail: "Restore previous Local notes."','continue_context_detail: ""'],
    ["private destination explanation",'local_destination: "Local (only for you)"','local_destination: ""'],
    ["shared destination explanation",'shared_destination: "Shared (to share with the PR)"','shared_destination: ""'],
    ["retained deletion","only_when: active_preparation_or_retained_result","only_when: active_preparation"],
    ["comment excerpts","list: compact_location_excerpt","list: number_title"],
    ["complete prose","detail: full_comment","detail: filename"],
    ["collapsed history","version: collapsed_details","version: always_visible"],
    ["visible capture warning","warning: always_visible","warning: collapsed_details"],
    ["marked previews","preview: single_line_160_with_ellipsis","preview: silently_truncated"],
    ["one location","location: list_only","location: list_and_detail"],
    ["internal diff tabs","ide_diff_host: editor_tab","ide_diff_host: separate_window"],
    ["same client diff surface","diff_host: same_client_surface","diff_host: external_app"],
    ["browser closes after opening diff","open_diff: closes_browser_on_success","open_diff: explicit_keeps_comment_accessible"],
    ["original range marking","lines: reveal_and_highlight_original_side","lines: current_head"],
    ["two independent rows","rows: [Local, Shared]","rows: [Local]"],
    ["comments footer placement","placement: footer_after_walkthrough_before_compare","placement: body_before_inventory_and_footer"],
    ["only the sole CLI destination defaults","destination_default: sole_cli_capability","destination_default: local"],
    ["conditional reveal","addComment: comments_block_born","addComment: always"],
    ["CLI capture choices","destination: cli_capabilities","destination: remember_last"],
    ["sole destination has no selector","destination_selector: multiple_cli_capabilities_only","destination_selector: always"],
    ["automatic compare retention","compare_notes: retained_automatically","compare_notes: manual_checkpoint"],
    ["destination placeholder","destination_prompt: placeholder_only","destination_prompt: menu_item"],
    ["selection preview only","preview: selected_text_only","preview: all_scopes"],
    ["aligned fields","field_alignment: shared_edges","field_alignment: natural_width"],
    ["nearby live target","live_target_placement: add_comment_group","live_target_placement: panel_top"],
    ["scope priority","scope_default: most_specific_available","scope_default: general"],
    ["frozen capture","freeze_capture_on_open: true","freeze_capture_on_open: false"],
    ["busy form","disable_while_saving: [save, cancel, inputs]","disable_while_saving: [save]"],
    ["successful close","close_on_success: true","close_on_success: false"],
    ["main panel visibility","visibility: main_panel_with_empty_states","visibility: existing_documents_only"],
    ["empty state requires reading","empty_state: after_successful_read","empty_state: before_read"],
    ["local empty state",'empty_local: "No local comments."','empty_local: ""'],
    ["shared empty state",'empty_shared: "No shared comments."','empty_shared: ""'],
    ["multiline","multiline: true","multiline: false"],
    ["accessible Save","accessible_save: tab_enter","accessible_save: ctrl_enter_only"],
    ["input dialog declaration","  - commentsComposer\n",""],
    ["pending review only","only_when: review_result_pending","only_when: result"],
    ["no extra row action","    initComments: {label: \"Create\"","    anotherComments: {label: \"Create\""],
    ["row controls outside product actions","actions:\n","actions:\n  initComments:\n    surface: both\n    situations: [review]\n"],
    ["no Add confirmation","addComment: {label: \"Add comment\", emphasis: secondary, confirms: false}","addComment: {label: \"Add comment\", emphasis: secondary, confirms: true}"],
])test("comments gate rejects "+name,()=>{
    assert.ok(yaml.includes(from),"mutation did not hit the contract");
    const broken=yaml.replace(from,to);
    assert.ok(validateCommentsSurface(broken).length>0,"mutation was accepted");
});
