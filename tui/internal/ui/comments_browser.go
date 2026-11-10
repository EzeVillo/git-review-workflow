package ui

import (
	"context"
	"regexp"
	"strconv"
	"strings"
	"unicode"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

type CommentsBrowser struct {
	Entries                           []domain.CommentPresentation
	Cursor, Offset                    int
	Diff, Error                       string
	ShowingDiff, Busy, ShowingDetails bool
	CanDelete                         bool
	Document                          domain.CommentDocument
	Report                            domain.CommentsReport
}

// Markdown and historical blobs come from the reviewed branch. Strip terminal
// sequences before layout so truncation cannot leave a partial escape behind.
func safeCommentText(text string) string {
	return strings.Map(func(r rune) rune {
		if r != '\n' && r != '\t' && unicode.IsControl(r) {
			return -1
		}
		return r
	}, ansi.Strip(text))
}

func (b *CommentsBrowser) Render(vp Viewport) string {
	if len(b.Entries) == 0 {
		return domain.CommentsEmpty + "\n\n" + domain.CommentsBrowserEmptyKeys
	}
	entry := b.Entries[b.Cursor]
	width := max(1, vp.Cols)
	ellipsis := "…"
	if vp.ASCII {
		ellipsis = "..."
	}
	header := []string{domain.CommentsEntries}
	if !b.ShowingDiff {
		count := min(3, max(1, (vp.Rows/3-1)/2))
		first := min(max(0, b.Cursor-count/2), max(0, len(b.Entries)-count))
		for i := first; i < min(len(b.Entries), first+count); i++ {
			prefix := "  "
			if i == b.Cursor {
				prefix = "> "
			}
			header = append(header, ansi.Truncate(prefix+safeCommentText(b.Entries[i].Label), width, ellipsis), ansi.Truncate("    "+safeCommentText(b.Entries[i].Preview), width, ellipsis))
		}
	} else {
		header = append(header, entry.Location)
	}
	if entry.Warning != "" {
		header = append(header, entry.Warning)
	}
	if b.ShowingDetails && entry.Version != "" {
		header = append(header, entry.Version)
	}
	header = append(header, "")
	body := entry.Body
	if b.ShowingDiff {
		body = entry.Preview + "\n\n" + b.Diff
	}
	lines := []string{}
	for _, line := range strings.Split(safeCommentText(body), "\n") {
		lines = append(lines, wrapLine(line, width)...)
	}
	wrapped := []string{}
	for _, line := range header {
		wrapped = append(wrapped, wrapLine(safeCommentText(line), width)...)
	}
	help := domain.CommentsBrowserKeys
	if vp.ASCII {
		help = domain.CommentsBrowserKeysASCII
	}
	if !b.ShowingDiff && !entry.CanOpenDiff {
		help = strings.ReplaceAll(strings.ReplaceAll(help, " · Enter diff", ""), " | Enter diff", "")
	}
	if b.CanDelete {
		if vp.ASCII {
			help += " | " + domain.CommentsDeleteEntryKey
		} else {
			help += " · " + domain.CommentsDeleteEntryKey
		}
	}
	footer := []string{}
	for _, line := range []string{b.Error, help} {
		footer = append(footer, wrapLine(safeCommentText(line), width)...)
	}
	height := max(1, vp.Rows-len(wrapped)-len(footer)-1)
	b.Offset = min(b.Offset, max(0, len(lines)-height))
	wrapped = append(wrapped, lines[b.Offset:min(len(lines), b.Offset+height)]...)
	return strings.Join(append(append(wrapped, ""), footer...), "\n")
}

func (m Model) handleCommentsBrowserKey(msg tea.KeyMsg) (Model, tea.Cmd) {
	b := m.commentsBrowser
	if m.commentsDiff != nil {
		b = m.commentsDiff
	}
	if b.Busy {
		return m, nil
	}
	switch msg.String() {
	case "esc", "q", "ctrl+c":
		m.commentsBrowser = nil
		m.commentsDiff = nil
	case "d":
		b.ShowingDetails = !b.ShowingDetails
		b.Offset = 0
	case "tab":
		b.ShowingDiff = false
		b.Offset = 0
	case "pgdown":
		b.Offset += max(1, m.Viewport.Rows/3)
	case "pgup":
		b.Offset = max(0, b.Offset-max(1, m.Viewport.Rows/3))
	case "j", "down":
		if m.commentsDiff != nil {
			b.Offset++
		} else if len(b.Entries) > 0 {
			b.ShowingDetails = false
			b.Cursor = (b.Cursor + 1) % len(b.Entries)
			b.Offset = 0
		}
	case "k", "up":
		if m.commentsDiff != nil {
			b.Offset = max(0, b.Offset-1)
		} else if len(b.Entries) > 0 {
			b.ShowingDetails = false
			b.Cursor = (b.Cursor + len(b.Entries) - 1) % len(b.Entries)
			b.Offset = 0
		}
	case "x", "delete":
		if !b.CanDelete || len(b.Entries) == 0 || m.commentsDiff != nil {
			return m, nil
		}
		args, err := domain.CommentsArgv(b.Report, "delete", b.Document.Kind, b.Document.Context, b.Entries[b.Cursor].Ordinal)
		if err != nil {
			b.Error = err.Error()
			return m, nil
		}
		m.confirm = ConfirmMutation("deleteCommentEntry", domain.CommentsDeleteEntryTitle, domain.CommentsDeleteEntryDetail, domain.CommentsDelete, currentStateToken(m.Panel), mutationRequest{action: "deleteCommentEntry", argv: &domain.Argv{Verb: "comments", Args: args}})
	case "enter":
		if m.commentsDiff != nil {
			b.ShowingDiff = true
			b.Offset = 0
			return m, nil
		}
		if len(b.Entries) == 0 || !b.Entries[b.Cursor].CanOpenDiff {
			return m, nil
		}
		args, err := domain.CommentsArgv(b.Report, "diff", b.Document.Kind, b.Document.Context, b.Entries[b.Cursor].Ordinal)
		if err != nil {
			b.Error = err.Error()
			return m, nil
		}
		b.Busy = true
		b.Error = ""
		return m, commentsHistoricalCmd(args, b.Document, b.Report, b.Entries[b.Cursor])
	}
	return m, nil
}

func commentsHistoricalCmd(args []string, doc domain.CommentDocument, report domain.CommentsReport, entry domain.CommentPresentation) tea.Cmd {
	return func() tea.Msg {
		recipe := host.InvokeReview(context.Background(), "comments", append(append([]string{}, args...), "--porcelain"))
		if mutationFailed(recipe) {
			return commentsQueryDone{result: recipe}
		}
		rendered := host.InvokeReview(context.Background(), "comments", args)
		if mutationFailed(rendered) {
			return commentsQueryDone{result: rendered}
		}
		var excerpt strings.Builder
		if entry.First > 0 {
			found := false
			for _, blob := range domain.ParseComments(recipe.Stdout).Records("comment-blob") {
				if blob[1] != entry.Side || blob[2] != "present" || len(blob) < 4 {
					continue
				}
				content := host.ReadCommentBlob(context.Background(), blob[3])
				if mutationFailed(content) {
					return commentsQueryDone{result: content}
				}
				lines := strings.Split(content.Stdout, "\n")
				if entry.First < 1 || entry.Last < entry.First || entry.Last > len(lines) {
					return commentsQueryDone{result: host.Result{ExitCode: 5, Stderr: domain.CommentsRangeUnavailable}}
				}
				for i := max(0, entry.First-4); i < min(len(lines), entry.Last+3); i++ {
					prefix := "  "
					if commentContainsLine(entry, i+1) {
						prefix = "> "
					}
					label := prefix + strconv.Itoa(i+1) + " | "
					excerpt.WriteString(label + lines[i] + "\n")
					marker, valid := commentColumnMarker(lines[i], i+1, entry, label)
					if !valid {
						return commentsQueryDone{result: host.Result{ExitCode: 5, Stderr: domain.CommentsRangeUnavailable}}
					}
					if marker != "" {
						excerpt.WriteString(marker + "\n")
					}
				}
				found = true
			}
			if !found {
				return commentsQueryDone{result: host.Result{ExitCode: 5, Stderr: domain.CommentsRangeUnavailable}}
			}
		}
		return commentsQueryDone{result: rendered, document: doc, report: report, excerpt: excerpt.String()}
	}
}

var diffHunk = regexp.MustCompile(`^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@`)

// The marker is outside the patch. Original old/new counters never use HEAD.
func markCommentLines(diff string, entry domain.CommentPresentation) string {
	if entry.First < 1 {
		return diff
	}
	old, fresh := 0, 0
	inHunk := false
	found := false
	lines := strings.Split(diff, "\n")
	rendered := []string{}
	for i, line := range lines {
		if match := diffHunk.FindStringSubmatch(line); match != nil {
			old, _ = strconv.Atoi(match[1])
			fresh, _ = strconv.Atoi(match[2])
			inHunk = true
			rendered = append(rendered, line)
			continue
		}
		if strings.HasPrefix(line, "diff --git ") {
			old, fresh = 0, 0
			inHunk = false
			rendered = append(rendered, line)
			continue
		}
		if !inHunk || len(line) == 0 {
			rendered = append(rendered, line)
			continue
		}
		number := fresh
		belongs := line[0] != '-'
		if entry.Side == "base" {
			number = old
			belongs = line[0] != '+'
		}
		marked := belongs && commentContainsLine(entry, number) && (line[0] == ' ' || line[0] == '+' || line[0] == '-')
		if line[0] == ' ' || line[0] == '-' {
			old++
		}
		if line[0] == ' ' || line[0] == '+' {
			fresh++
		}
		prefix := "  "
		if marked {
			prefix = "> "
			found = true
		}
		lines[i] = prefix + line
		rendered = append(rendered, lines[i])
		if marked {
			marker, valid := commentColumnMarker(line[1:], number, entry, prefix+line[:1])
			if valid && marker != "" {
				rendered = append(rendered, marker)
			}
		}
	}
	if !found {
		return domain.CommentsRangeOutsideHunks + "\n\n" + diff
	}
	return domain.CommentsRangeMarker + "\n\n" + strings.Join(rendered, "\n")
}

func commentContainsLine(entry domain.CommentPresentation, line int) bool {
	return line >= entry.First && line <= entry.Last && !(entry.StartColumn > 0 && entry.EndColumn == 1 && line == entry.Last)
}

// Carets work in monochrome and ASCII too; they point at text, not whole rows.
func commentColumnMarker(text string, line int, entry domain.CommentPresentation, prefix string) (string, bool) {
	if entry.StartColumn == 0 || line < entry.First || line > entry.Last {
		return "", true
	}
	text = strings.TrimSuffix(text, "\r")
	first, end := 1, 1
	for _, r := range text {
		end++
		if r > 0xffff {
			end++
		}
	}
	if line == entry.First {
		first = entry.StartColumn
	}
	if line == entry.Last {
		end = entry.EndColumn
	}
	a, b, ok := domain.CommentColumnOffsets(text, first, end)
	if !ok {
		return "", false
	}
	if !commentContainsLine(entry, line) {
		return "", true
	}
	width := func(s string) int {
		n := 0
		for i, part := range strings.Split(s, "\t") {
			if i > 0 {
				n += 8 - n%8
			}
			n += ansi.StringWidth(part)
		}
		return n
	}
	start := width(prefix + text[:a])
	return strings.Repeat(" ", start) + strings.Repeat("^", max(1, width(prefix+text[:b])-start)), true
}
