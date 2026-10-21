package ui

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

type CommentsForm struct {
	Destinations                                   []string
	Text                                           textarea.Model
	Path, Start, End                               textinput.Model
	Destination, Side, Guard, ContextChoice, Error string
	Focus                                          int
	Scope                                          string
	Busy                                           bool
}

func newCommentsForm(guard, path string, destinations []string) *CommentsForm {
	body := textarea.New()
	body.SetWidth(64)
	body.SetHeight(10)
	body.CharLimit = 0
	body.Placeholder = domain.CommentsBodyPlaceholder
	body.Focus()
	p, s, e := textinput.New(), textinput.New(), textinput.New()
	p.SetValue(path)
	s.CharLimit = 24
	e.CharLimit = 24
	scope := "general"
	if path != "" {
		scope = "file"
	}
	destination := ""
	if len(destinations) == 1 {
		destination = destinations[0]
	}
	return &CommentsForm{Destinations: destinations, Destination: destination, Scope: scope, Text: body, Path: p, Start: s, End: e, Guard: guard, Side: "head", Focus: 1}
}
func (f *CommentsForm) allowed(kind string) bool {
	for _, destination := range f.Destinations {
		if kind == destination {
			return true
		}
	}
	return false
}
func (f *CommentsForm) valid() bool {
	if !f.allowed(f.Destination) || strings.TrimSpace(f.Text.Value()) == "" {
		return false
	}
	if f.Scope == "general" {
		return true
	}
	if f.Path.Value() == "" {
		return false
	}
	if f.Scope == "file" {
		return true
	}
	start, sc, a := domain.ParseCommentPosition(f.Start.Value())
	end, ec, b := domain.ParseCommentPosition(f.End.Value())
	return a && b && end >= start && (sc == 0) == (ec == 0) && (sc == 0 || end > start || ec > sc)
}
func (f *CommentsForm) focus() tea.Cmd {
	f.Text.Blur()
	f.Path.Blur()
	f.Start.Blur()
	f.End.Blur()
	switch f.Focus {
	case 1:
		return f.Text.Focus()
	case 2:
		return f.Path.Focus()
	case 4:
		return f.Start.Focus()
	case 5:
		return f.End.Focus()
	}
	return nil
}
func (f *CommentsForm) render(vp Viewport) string {
	f.Text.SetWidth(max(24, vp.Cols-8))
	f.Text.SetHeight(max(3, min(10, vp.Rows-16)))
	f.Text.Prompt = "| "
	marker := func(n int) string {
		if f.Focus == n {
			return "> "
		}
		return "  "
	}
	destination := f.Destination
	if destination == "local" {
		destination = domain.CommentsLocalDestination
	} else if destination == "shared" {
		destination = domain.CommentsSharedDestination
	} else {
		destination = domain.CommentsDestination
	}
	arrows := "←/→"
	help := domain.CommentsKeyboardHelp
	if vp.ASCII {
		arrows = "left/right"
		help = domain.CommentsKeyboardASCII
	}
	scope := domain.CommentsGeneral
	if f.Scope == "file" {
		scope = domain.CommentsScopeFile
	}
	if f.Scope == "selection" {
		scope = domain.CommentsScopeSelection
	}
	submit, cancel := domain.CommentsSubmit, domain.CommentsCancel
	if f.Busy {
		submit = domain.CommentsSaving
		cancel += " (" + domain.CommentsDisabled + ")"
	}
	destinationField := ""
	if len(f.Destinations) > 1 {
		destinationField = fmt.Sprintf("%s%s: %s (%s)\n", marker(0), domain.CommentsDestinationLabel, destination, arrows)
	}
	return marker(8) + domain.CommentsScope + ": " + scope + " (" + arrows + ")\n" + fmt.Sprintf("%s\n\n%s%s%s\n%s%s: %s\n%s%s: %s (%s)\n%s%s: %s\n%s%s: %s\n\n%s[%s]  %s[%s]\n%s\n\n%s", domain.CommentsAdd, destinationField, marker(1), domain.CommentsBody+"\n"+f.Text.View(), marker(2), domain.CommentsPathLabel, f.Path.View(), marker(3), domain.CommentsSideLabel, f.Side, arrows, marker(4), domain.CommentsFirstLineLabel, f.Start.View(), marker(5), domain.CommentsLastLineLabel, f.End.View(), marker(6), submit, marker(7), cancel, f.Error, help)
}
func (m Model) beginAddComment() (Model, tea.Cmd) {
	report := domain.ParseComments(m.Panel.Comments)
	if report.Guard() == "" || len(report.Destinations("add")) == 0 {
		return m, nil
	}
	path := m.Panel.CurrentPath.Display
	if m.Panel.Situation == domain.SituationFinishConflict {
		path = ""
	}
	form := newCommentsForm(report.Guard(), path, report.Destinations("add"))
	for _, id := range report.Records("comments-identity") {
		if id[0] == "ambiguous" {
			items := []SelectItem{{Label: domain.CommentsNewContext, Detail: domain.CommentsNewContextDetail, Value: "*"}}
			for _, c := range report.Records("comments-candidate") {
				detail := domain.CommentsContinueContextDetail
				if len(c) > 2 && c[2] != "" {
					detail += " " + c[2]
				}
				items = append(items, SelectItem{Label: domain.CommentsContinueContext + ": " + c[1], Detail: detail, Value: c[0]})
			}
			hint := domain.CommentsLocalContextHint
			if form.allowed("shared") {
				hint = domain.CommentsContextHint
			}
			m.selectOverlay = &SelectOverlay{Title: domain.CommentsChooseContext, Notice: hint, Items: items, OnPick: func(choice string) selectResult { form.ContextChoice = choice; return selectResult{commentForm: form} }}
			return m, nil
		}
	}
	m.commentsForm = form
	return m, form.focus()
}
func (m Model) handleCommentsKey(msg tea.KeyMsg) (Model, tea.Cmd) {
	form := m.commentsForm
	if form == nil {
		return m, nil
	}
	if form.Busy {
		return m, nil
	}
	switch msg.String() {
	case "esc":
		m.commentsForm = nil
		return m, nil
	case "tab":
		form.Focus = (form.Focus + 1) % 9
		if form.Focus == 0 && len(form.Destinations) == 1 {
			form.Focus = 1
		}
		return m, form.focus()
	case "shift+tab":
		form.Focus = (form.Focus + 8) % 9
		if form.Focus == 0 && len(form.Destinations) == 1 {
			form.Focus = 8
		}
		return m, form.focus()
	case "left", "right", " ":
		if form.Focus == 8 {
			scopes := []string{"general"}
			if form.Path.Value() != "" {
				scopes = []string{"file", "general"}
			}
			if form.Path.Value() != "" && form.Start.Value() != "" && form.End.Value() != "" {
				scopes = []string{"selection", "file", "general"}
			}
			index := 0
			for i, scope := range scopes {
				if scope == form.Scope {
					index = i
				}
			}
			form.Scope = scopes[(index+1)%len(scopes)]
			return m, nil
		}
		if form.Focus == 0 {
			for i, kind := range form.Destinations {
				if kind == form.Destination {
					form.Destination = form.Destinations[(i+1)%len(form.Destinations)]
					return m, nil
				}
			}
			if len(form.Destinations) > 0 {
				form.Destination = form.Destinations[0]
			}
			return m, nil
		}
		if form.Focus == 3 {
			if form.Side == "head" {
				form.Side = "base"
			} else {
				form.Side = "head"
			}
			return m, nil
		}
	case "enter":
		if form.Focus == 7 {
			m.commentsForm = nil
			return m, nil
		}
		if form.Focus == 6 {
			return m.submitComment()
		}
	case "ctrl+enter":
		return m.submitComment()
	}
	var cmd tea.Cmd
	switch form.Focus {
	case 1:
		form.Text, cmd = form.Text.Update(msg)
	case 2:
		form.Path, cmd = form.Path.Update(msg)
	case 4:
		form.Start, cmd = form.Start.Update(msg)
	case 5:
		form.End, cmd = form.End.Update(msg)
	}
	if form.Focus == 4 || form.Focus == 5 {
		if form.Start.Value() != "" && form.End.Value() != "" {
			form.Scope = "selection"
		}
	}
	if form.Focus == 2 {
		if form.Path.Value() == "" {
			form.Scope = "general"
		} else {
			form.Scope = "file"
		}
	}
	return m, cmd
}
func (m Model) submitComment() (Model, tea.Cmd) {
	f := m.commentsForm
	if f == nil || !f.valid() {
		return m, nil
	}
	if m.lock.Busy() {
		f.Error = domain.MutationDiscardedNotice
		return m, nil
	}
	report := domain.ParseComments(m.Panel.Comments)
	if report.Guard() != f.Guard {
		f.Error = domain.StaleNotice
		return m, nil
	}
	args, err := domain.CommentsArgv(report, "add", f.Destination, "", 0)
	if err != nil {
		f.Error = err.Error()
		return m, nil
	}
	args = append(args, "--stdin")
	if f.ContextChoice == "*" {
		args = append(args, "--new-context")
	} else if f.ContextChoice != "" {
		args = append(args, "--use-context", f.ContextChoice)
	}
	if f.Scope != "general" && f.Path.Value() != "" {
		args = append(args, "--path", f.Path.Value(), "--side", f.Side)
		if f.Scope == "selection" {
			start, sc, _ := domain.ParseCommentPosition(f.Start.Value())
			end, ec, _ := domain.ParseCommentPosition(f.End.Value())
			args = append(args, "--start-line", strconv.Itoa(start), "--end-line", strconv.Itoa(end))
			if sc > 0 {
				args = append(args, "--start-column", strconv.Itoa(sc), "--end-column", strconv.Itoa(ec))
			}
		}
	}
	f.Busy = true
	return m.beginMutation(mutationRequest{action: "addComment", argv: &domain.Argv{Verb: "comments", Args: args}, stdin: f.Text.Value(), hasInput: true, latestComments: true}, currentStateToken(m.Panel))
}

type commentsQueryDone struct {
	excerpt  string
	title    string
	result   host.Result
	document domain.CommentDocument
	report   domain.CommentsReport
	entries  bool
}
type commentsEditorDone struct{ err error }

func commentsQueryCmd(args []string, doc domain.CommentDocument, report domain.CommentsReport, entries bool) tea.Cmd {
	return func() tea.Msg {
		return commentsQueryDone{title: domain.CommentsDiff, result: host.InvokeReview(context.Background(), "comments", args), document: doc, report: report, entries: entries}
	}
}
func (m Model) beginCommentsRow(action, variant string) (Model, tea.Cmd) {
	report := domain.ParseComments(m.Panel.Comments)
	index, err := strconv.Atoi(variant)
	docs := report.Documents()
	if err != nil || index < 0 || index >= len(docs) {
		return m, nil
	}
	doc := docs[index]
	if action == "copyCommentPath" {
		if doc.Kind != "local" || doc.Presence != "present" {
			return m, nil
		}
		host.CopyOSC52(doc.Path)
		m.statusLine = domain.CommentsPathCopySent
		return m, nil
	}
	if action == "openComments" {
		cwd, _ := os.Getwd()
		cmd, reason, ok := host.OpenInEditorCmd(doc.Path, cwd)
		if !ok {
			m.statusLine = reason
			return m, nil
		}
		return m, tea.ExecProcess(cmd, func(err error) tea.Msg { return commentsEditorDone{err} })
	}
	operation := map[string]string{"deleteComments": "delete", "initComments": "init", "renumberComments": "renumber", "openCommentDiff": "entries", "prepareSharedComments": "prepare"}[action]
	args, err := domain.CommentsArgv(report, operation, doc.Kind, doc.Context, 0)
	if err != nil {
		m.statusLine = err.Error()
		return m, nil
	}
	if operation == "delete" {
		m.confirm = ConfirmMutation("deleteComments", domain.CommentsDeleteTitle, domain.CommentsDeleteDetail, domain.CommentsDelete, currentStateToken(m.Panel), mutationRequest{action: action, argv: &domain.Argv{Verb: "comments", Args: args}})
		return m, nil
	}
	if operation == "entries" {
		return m, commentsQueryCmd(args, doc, report, true)
	}
	if operation == "prepare" {
		m.selectOverlay = &SelectOverlay{Title: domain.CommentsDeliveryTitle, Items: []SelectItem{{Label: domain.CommentsCompareDelivery, Value: "compare"}, {Label: domain.CommentsRetryDelivery, Value: "prepare"}}, OnPick: func(value string) selectResult {
			if value == "compare" {
				return selectResult{cmd: commentsQueryCmd(append(append([]string{}, args...), "--check"), doc, report, false)}
			}
			return selectResult{done: &mutationRequest{action: action, argv: &domain.Argv{Verb: "comments", Args: args}}}
		}}
		return m, nil
	}
	return m.beginMutation(mutationRequest{action: action, argv: &domain.Argv{Verb: "comments", Args: args}}, currentStateToken(m.Panel))
}
func (m Model) handleCommentsQuery(msg commentsQueryDone) (Model, tea.Cmd) {
	if mutationFailed(msg.result) {
		if m.commentsBrowser != nil {
			m.commentsBrowser.Busy = false
			m.commentsBrowser.Error = failureMessage("comments", msg.result)
			if msg.result.ExitCode == 4 {
				m.commentsBrowser.Error = domain.StaleNotice
			}
			return m, nil
		}
		m.statusLine = failureMessage("comments", msg.result)
		if msg.result.ExitCode == 4 {
			m.statusLine = domain.StaleNotice
		}
		return m, nil
	}
	if !msg.entries {
		if m.commentsBrowser != nil && m.commentsBrowser.Busy {
			b := m.commentsBrowser
			entry := b.Entries[b.Cursor]
			m.commentsDiff = &CommentsBrowser{
				Entries: []domain.CommentPresentation{entry}, ShowingDiff: true,
				Diff: msg.excerpt + "\n" + markCommentLines(msg.result.Stdout, entry),
			}
			m.commentsBrowser = nil
			return m, nil
		}
		m.textOverlay = &TextOverlay{Title: msg.title, Body: msg.result.Stdout}
		return m, nil
	}
	entries := domain.ParseComments(msg.result.Stdout)
	presentations := []domain.CommentPresentation{}
	for _, entry := range entries.Records("comment-entry") {
		presentations = append(presentations, domain.PresentComment(entries, entry))
	}
	if len(presentations) == 0 && m.commentsBrowser == nil {
		m.statusLine = domain.CommentsEmpty
		return m, nil
	}
	report := msg.report
	rows := []domain.CommentRecord{}
	for _, row := range report.Rows {
		if row.Tag != "comments-document" {
			rows = append(rows, row)
		}
	}
	for _, row := range entries.Rows {
		if row.Tag == "comments-document" {
			rows = append(rows, row)
		}
	}
	report.Rows = rows
	cursor := 0
	if m.commentsBrowser != nil {
		cursor = min(m.commentsBrowser.Cursor, max(0, len(presentations)-1))
	}
	canDelete := false
	for _, row := range report.Records("comments-context") {
		if row[0] == msg.document.Context && (row[2] == "active" || row[2] == "result" || row[2] == "repository" && msg.document.Kind == "local") {
			canDelete = true
		}
	}
	m.commentsBrowser = &CommentsBrowser{Entries: presentations, Cursor: cursor, Document: msg.document, Report: report, CanDelete: canDelete}
	return m, nil
}

func commentsControls(m domain.PanelModel) []Control {
	r := domain.ParseComments(m.Comments)
	capture := r.Guard() != "" && (m.Situation == domain.SituationReview || m.Situation == domain.SituationFinishConflict)
	visible := false
	for _, doc := range r.Documents() {
		if commentDocumentVisible(r, doc) {
			visible = true
		}
	}
	controls := []Control{}
	if capture {
		controls = append(controls, Control{ID: "addComment", Enabled: !m.Busy})
	}
	if !visible {
		return controls
	}
	for index, doc := range r.Documents() {
		if !commentDocumentVisible(r, doc) {
			continue
		}
		variant := strconv.Itoa(index)
		enabled := !m.Busy && doc.Revision != "unreadable"
		editable := false
		for _, c := range r.Records("comments-context") {
			if c[0] == doc.Context && (c[2] == "active" || c[2] == "result" || c[2] == "repository" && doc.Kind == "local") {
				editable = true
			}
		}
		if doc.Presence == "present" {
			controls = append(controls, Control{ID: "openComments", Variant: variant, Enabled: !m.Busy})
			if doc.Kind == "local" {
				controls = append(controls, Control{ID: "copyCommentPath", Variant: variant, Enabled: !m.Busy})
			}
			if editable {
				controls = append(controls, Control{ID: "renumberComments", Variant: variant, Enabled: enabled})
			}
			controls = append(controls, Control{ID: "openCommentDiff", Variant: variant, Enabled: enabled})
			if editable {
				controls = append(controls, Control{ID: "deleteComments", Variant: variant, Enabled: enabled})
			}
		} else if capture {
			controls = append(controls, Control{ID: "initComments", Variant: variant, Enabled: enabled})
		}
		if doc.Kind == "shared" {
			for _, c := range r.Records("comments-context") {
				if c[0] == doc.Context && c[1] == "review" && c[2] == "result" {
					for _, d := range r.Records("comments-delivery") {
						if d[0] == doc.Context && d[1] == "pending" {
							controls = append(controls, Control{ID: "prepareSharedComments", Variant: variant, Enabled: enabled})
						}
					}
				}
			}
		}
	}
	return controls
}
func renderComments(b *builder, m domain.PanelModel) {
	r := domain.ParseComments(m.Comments)
	controls := commentsControls(m)
	mainPanel := m.Situation == domain.SituationNoReview && (m.Comments != "" || m.CommentsError != "")
	visible := false
	for _, d := range r.Documents() {
		if commentDocumentVisible(r, d) {
			visible = true
		}
	}
	if visible || mainPanel {
		b.heading(domain.CommentsTitle)
	}
	emptyRow := func(kind, label, text string) {
		if !mainPanel || m.Comments == "" || m.CommentsError != "" || len(r.Records("comments-diagnostic")) > 0 {
			return
		}
		for _, doc := range r.Documents() {
			if doc.Kind == kind && commentDocumentVisible(r, doc) {
				return
			}
		}
		b.rowHeader(label, "", "")
		b.text(text)
	}
	labels := map[domain.ControlID]string{"deleteComments": domain.CommentsDelete, "addComment": domain.CommentsAdd, "initComments": domain.CommentsCreate, "openComments": domain.CommentsOpen, "copyCommentPath": domain.CommentsCopyPath, "renumberComments": domain.CommentsRenumber, "openCommentDiff": domain.CommentsDiff, "prepareSharedComments": domain.CommentsPrepare}
	for _, c := range controls {
		if c.Variant == "" {
			b.button(c.ID, "", labels[c.ID], b.st.secondary, c.Enabled)
		}
	}
	emptyRow("local", domain.CommentsLocal, domain.CommentsEmptyLocal)
	if visible {
		for index, doc := range r.Documents() {
			if !commentDocumentVisible(r, doc) {
				continue
			}
			label := domain.CommentsLocal
			if doc.Kind == "shared" {
				label = domain.CommentsShared
			}
			for _, c := range r.Records("comments-context") {
				if c[0] == doc.Context && c[2] != "active" {
					label = c[4] + " · " + label
				}
			}
			count := ""
			if doc.Count != nil {
				count = strconv.Itoa(*doc.Count)
			}
			b.rowHeader(label, "", count)
			buttons := []rowButton{}
			for _, c := range controls {
				if c.Variant == strconv.Itoa(index) {
					buttons = append(buttons, rowButton{id: c.ID, variant: c.Variant, label: labels[c.ID], style: b.st.secondary, enabled: c.Enabled})
				}
			}
			if len(buttons) > 0 {
				b.buttonRow(buttons...)
			}
		}
	}
	emptyRow("shared", domain.CommentsShared, domain.CommentsEmptyShared)
	for _, d := range r.Records("comments-diagnostic") {
		b.stderrBlock(d[2])
	}
	if m.CommentsError != "" {
		b.stderrBlock(m.CommentsError)
	}
}

func commentDocumentVisible(r domain.CommentsReport, doc domain.CommentDocument) bool {
	if doc.Presence == "present" {
		return true
	}
	if doc.Kind == "shared" {
		for _, d := range r.Records("comments-delivery") {
			if d[0] == doc.Context && d[1] == "pending" {
				return true
			}
		}
	}
	return false
}
