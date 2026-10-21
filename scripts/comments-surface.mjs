function block(yaml,key) {
    return yaml.split(new RegExp(`^${key}:\\s*$`,"m"))[1]?.split(/^[a-z_][a-z0-9_]*:/m)[0] ?? "";
}
export function validateCommentsSurface(yaml) {
    const errors=[];
    const require=(ok,message)=>{if(!ok)errors.push(message);};
    const rows=block(yaml,"comments_rows");
    require(/^ {2}rows:\s*\[Local, Shared\]\s*$/m.test(rows),"Comments must report Local and Shared, in order");
    require(/^ {2}placement:\s*footer_after_walkthrough_before_compare\s*$/m.test(rows),"Comments belong in the footer between Walkthrough and Compare");
    require(/^ {2}destination_default:\s*sole_cli_capability\s*$/m.test(rows),"Only a sole CLI capability defaults the destination");
    require(/^ {2}visibility:\s*main_panel_with_empty_states\s*$/m.test(rows),"The main panel keeps Comments visible with independent empty states");
    require(/^ {2}empty_state:\s*after_successful_read\s*$/m.test(rows),"Empty comments require a successful read");
    require(/^ {2}empty_local:\s*"No local comments\."\s*$/m.test(rows),"Local needs its own empty state");
    require(/^ {2}empty_shared:\s*"No shared comments\."\s*$/m.test(rows),"Shared needs its own empty state");
    require(/^ {2}live_target_placement:\s*add_comment_group\s*$/m.test(rows),"Live target belongs next to Add comment");
    const controls=rows.split(/^ {2}controls:\s*$/m)[1] ?? "";
    const definitions=[...controls.matchAll(/^ {4}(\w+):\s*\{([^\n]*)\}/gm)];
    const labels={deleteComments:"Delete",initComments:"Create",openComments:"Open",copyCommentPath:"Copy path",renumberComments:"Renumber",openCommentDiff:"View changes",prepareSharedComments:"Prepare"};
    require(definitions.length===7 && definitions.every(d=>d[1] in labels),"Comments must have exactly seven document controls");
    for(const [id,label] of Object.entries(labels)) {
        const definition=definitions.find(d=>d[1]===id)?.[2] ?? "";
        const icon={openComments:"file",copyCommentPath:"copy",renumberComments:"numbered",openCommentDiff:"eye",deleteComments:"trash"}[id];
        const identity=icon ? definition.includes('label: null') && definition.includes(`accessible_name: "${label}"`) : definition.includes(`label: "${label}"`);
        require(identity && definition.includes(`confirms: ${id==="deleteComments"}`),`${id} label/confirmation drift`);
        if(icon) require(definition.includes('emphasis: icon') && definition.includes(`icon: ${icon},`),`${id} requires its declared semantic icon`);
        if(id==="prepareSharedComments") require(/only_when:\s*review_result_pending\b/.test(definition),"Prepare is limited to pending review results");
        if(id==="copyCommentPath") require(/only_when:\s*local_document_present\b/.test(definition),"Copy path is limited to existing Local documents");
        if(id==="deleteComments") require(/only_when:\s*active_preparation_or_retained_result\b/.test(definition),"Delete includes retained results without deleting a delivered copy");
    }
    const actions=block(yaml,"actions");
    const actionIDs=[...actions.matchAll(/^ {2}(\w+):\s*$/gm)].map(m=>m[1]);
    require(actionIDs.length===28 && actionIDs.includes("addComment") && !actionIDs.includes("saveComments"),"Comments require the 28-action matrix without Save comments");
    for(const id of Object.keys(labels))require(!actionIDs.includes(id),`${id} is a document control, not a product action`);
    const headers=rows.split(/^ {2}header_controls:\s*$/m)[1]?.split(/^ {2}controls:/m)[0] ?? "";
    for(const [id,label] of [["addComment","Add comment"]])require(new RegExp(`^ {4}${id}:.*label: "${label}".*confirms: false` ,"m").test(headers),`${id} must not confirm`);
    require(/^ {2}addComment:\s*comments_block_born\s*$/m.test(block(yaml,"reveal_conditions")),"Add comment reveals only when its block is born");
    const dialogs=block(yaml,"input_dialogs");
    for(const id of ["commentsComposer","commentsContext","commentEntry","commentsDelivery"])require(new RegExp(`^ {2}- ${id}\\s*$`,"m").test(dialogs),`${id} input dialog must be declared`);
    const composer=block(yaml,"comments_composer");
    for(const field of ["context_prompt","new_context_label","new_context_detail","continue_context_label","continue_context_detail","context_shared_note","context_local_note","local_destination","shared_destination"])
        require(new RegExp(`^ {2}${field}:\\s*"[^"\\n]+"\\s*$`,"m").test(composer),`Comments must explain ${field}`);
    require(/^ {2}selection_coordinates:\s*utf16_1based_end_exclusive\s*$/m.test(composer),"Comments must retain exact UTF-16 selection endpoints");
    require(/^ {2}selection_label:\s*"Selected code"\s*$/m.test(composer),"Selection scope describes the selected code fragment");
    require(/^ {2}body_label:\s*"Comment"\s*$/m.test(composer),"The comment field needs a visible label");
    require(/^ {2}destination_selector:\s*multiple_cli_capabilities_only\s*$/m.test(composer),"Only multiple CLI destinations need a selector");
    require(/^ {2}compare_notes:\s*retained_automatically\s*$/m.test(composer),"Compare notes must be retained automatically");
    const browser=block(yaml,"comments_browser");
    require(/open_diff_scope: \[selection, file\]/.test(browser),"General comments cannot open a diff");
    require(/delete_entry: preserve_other_entries_and_numbers/.test(browser),"Deleting an entry preserves other comments");
    require(/deleteCommentEntry:.*confirms: true/.test(browser),"Individual deletion must confirm");
    require(/after_delete: select_next_or_previous_keep_browser_open/.test(browser),"Deletion keeps the browser open");
    for(const [field,value] of Object.entries({list:"compact_location_excerpt",detail:"full_comment",version:"collapsed_details",warning:"always_visible",preview:"single_line_160_with_ellipsis",location:"list_only",diff_host:"same_client_surface",ide_diff_host:"editor_tab",open_diff:"closes_browser_on_success",lines:"reveal_and_highlight_original_side"}))
        require(new RegExp(`^ {2}${field}:\\s*${value}\\s*$`,"m").test(browser),`Comment browser ${field} drift`);
    require(/^ {2}destination_prompt:\s*placeholder_only\s*$/m.test(composer),"Destination prompt must not be a menu choice");
    require(/^ {2}preview:\s*selected_text_only\s*$/m.test(composer),"Only selected text needs a preview");
    require(/^ {2}field_alignment:\s*shared_edges\s*$/m.test(composer),"Composer fields must share their edges");
    require(/^ {2}scope:\s*\[selection, file, general\]\s*$/m.test(composer),"Comments require selection, file and general scopes");
    require(/^ {2}scope_default:\s*most_specific_available\s*$/m.test(composer),"Comments must prioritize the most specific available scope");
    require(/^ {2}freeze_capture_on_open:\s*true\s*$/m.test(composer),"Capture must stay fixed while composing");
    require(/^ {2}disable_while_saving:\s*\[save, cancel, inputs\]\s*$/m.test(composer),"Saving must disable the form");
    require(/^ {2}close_on_success:\s*true\s*$/m.test(composer),"Successful save must close the composer");
    require(/^ {2}multiline:\s*true\s*$/m.test(composer),"Comments require multiline composition");
    require(/^ {2}destination:\s*cli_capabilities\s*$/m.test(composer),"Capture destinations come from CLI capabilities");
    require(/^ {2}accessible_save:\s*tab_enter\s*$/m.test(composer),"Save needs a keyboard alternative to Ctrl+Enter");
    require(/keys:\s*\{newline: enter, save: ctrl\+enter, cancel: esc\}/.test(composer),"Composer keys must stay local to the form");
    return errors;
}

/** The existing reveal gate takes the condition; its call must also test block birth. */
export function validateCommentReveal(gate,caller) {
    const errors=[];
    if(!/commentsBlockBorn/.test(gate) || !/(?:!commentsBlockBorn|!comments_block_born)/.test(gate))errors.push("reveal gate must reject an unchanged comments block");
    const lines=caller.split(/\r?\n/).filter(line=>/revealPanel|PanelReveal\.Reveal/.test(line) && /addComment|ADD_COMMENT|AddComment/.test(line));
    if(lines.length!==1 || !/\bborn\b/.test(lines[0]))errors.push("Add comment reveal must be guarded by block birth");
    return errors;
}
