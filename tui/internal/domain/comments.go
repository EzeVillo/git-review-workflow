package domain

import (
	"fmt"
	"strconv"
	"strings"
	"unicode/utf16"
)

type CommentRecord struct {
	Tag    string
	Fields []string
}
type CommentDocument struct {
	Path, Context, Kind, Presence, Revision string
	Count                                   *int
}
type CommentsReport struct{ Rows []CommentRecord }

func (r CommentsReport) SupportsAddReply() bool {
	for _, fields := range r.Records("comments-add-reply") {
		if fields[0] == "1" {
			return true
		}
	}
	return false
}

type CommentsAddReply struct {
	Before, After string
	Report        string
}

func ParseCommentsAddReply(text, document string) (CommentsAddReply, bool) {
	lines := strings.Split(strings.TrimRight(text, "\r\n"), "\n")
	header := strings.Split(strings.TrimSuffix(lines[0], "\r"), "\t")
	if len(header) != 4 || header[0] != "comments-add-result" || header[1] != "1" ||
		!stateGuardPattern.MatchString(header[2]) || !stateGuardPattern.MatchString(header[3]) ||
		lines[len(lines)-1] != "comments-add-result-end\t1" {
		return CommentsAddReply{}, false
	}
	body := strings.Join(lines[1:len(lines)-1], "\n")
	report := ParseComments(body)
	guard := report.Guard()
	identity := report.Records("comments-identity")
	if !stateGuardPattern.MatchString(guard) || len(identity) != 1 || identity[0][0] != "resolved" {
		return CommentsAddReply{}, false
	}
	active := ""
	for _, fields := range report.Records("comments-context") {
		if fields[2] == "active" {
			if active != "" || fields[3] != guard {
				return CommentsAddReply{}, false
			}
			active = fields[0]
		}
	}
	for _, doc := range report.Documents() {
		if active != "" && doc.Context == active && doc.Kind == document && doc.Presence == "present" &&
			stateGuardPattern.MatchString(doc.Revision) && doc.Count != nil && *doc.Count > 0 {
			return CommentsAddReply{Before: header[2], After: header[3], Report: body}, true
		}
	}
	return CommentsAddReply{}, false
}

func ParseComments(text string) CommentsReport {
	minimum := map[string]int{"comments-capability": 2, "comments-owner": 2, "comments-context": 5, "comments-guard": 1, "comments-document": 5, "comments-count": 2, "comments-diagnostic": 3, "comments-identity": 2, "comments-candidate": 2, "comments-delivery": 3, "comments-capture": 3, "comment-body": 2, "comment-scope": 3, "comment-entry": 4, "comment-version": 3, "comment-path": 3, "comment-location": 4, "comment-unversioned": 1, "comment-diagnostic": 3, "comment-diff": 3, "comment-blob": 3, "comments-delivery-file": 4}
	r := CommentsReport{Rows: []CommentRecord{}}
	minimum["comment-columns"] = 4
	minimum["comments-add-reply"] = 1
	for _, line := range strings.Split(text, "\n") {
		f := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if n, ok := minimum[f[0]]; ok && len(f) > n {
			r.Rows = append(r.Rows, CommentRecord{Tag: f[0], Fields: f[1:]})
		}
	}
	return r
}

// ParseCommentPosition accepts a line or a 1-based UTF-16 line:column endpoint.
func ParseCommentPosition(value string) (line, column int, ok bool) {
	parts := strings.Split(value, ":")
	if len(parts) > 2 {
		return 0, 0, false
	}
	positive := func(s string) (int, bool) {
		if s == "" || strings.IndexFunc(s, func(r rune) bool { return r < '0' || r > '9' }) >= 0 {
			return 0, false
		}
		n, err := strconv.Atoi(s)
		return n, err == nil && n > 0
	}
	line, ok = positive(parts[0])
	if !ok {
		return 0, 0, false
	}
	if len(parts) == 2 {
		column, ok = positive(parts[1])
	}
	return
}

// CommentColumnOffsets maps UTF-16 columns to UTF-8 byte offsets, rejecting
// coordinates inside a surrogate pair rather than shifting the selected text.
func CommentColumnOffsets(text string, first, end int) (int, int, bool) {
	startByte, endByte, units := -1, -1, 1
	for i, r := range text {
		if units == first {
			startByte = i
		}
		if units == end {
			endByte = i
		}
		units += utf16.RuneLen(r)
	}
	if units == first {
		startByte = len(text)
	}
	if units == end {
		endByte = len(text)
	}
	return startByte, endByte, startByte >= 0 && endByte >= startByte
}
func (r CommentsReport) Records(tag string) [][]string {
	rows := [][]string{}
	for _, row := range r.Rows {
		if row.Tag == tag {
			rows = append(rows, row.Fields)
		}
	}
	return rows
}
func (r CommentsReport) Destinations(operation string) []string {
	destinations := []string{}
	for _, row := range r.Records("comments-capability") {
		if row[0] != operation || (row[1] != "local" && row[1] != "shared") {
			continue
		}
		duplicate := false
		for _, kind := range destinations {
			if kind == row[1] {
				duplicate = true
			}
		}
		if !duplicate {
			destinations = append(destinations, row[1])
		}
	}
	return destinations
}
func (r CommentsReport) Guard() string {
	for _, f := range r.Records("comments-guard") {
		if len(f) > 0 {
			return f[0]
		}
	}
	return ""
}
func (r CommentsReport) Documents() []CommentDocument {
	docs := []CommentDocument{}
	for _, f := range r.Records("comments-document") {
		if len(f) < 5 {
			continue
		}
		d := CommentDocument{Path: f[0], Context: f[1], Kind: f[2], Presence: f[3], Revision: f[4]}
		for _, c := range r.Records("comments-count") {
			if len(c) >= 2 && c[0] == d.Path {
				if n, err := strconv.Atoi(c[1]); err == nil && n >= 0 {
					d.Count = &n
				}
			}
		}
		docs = append(docs, d)
	}
	return docs
}
func CommentsArgv(r CommentsReport, operation, document, context string, ordinal int) ([]string, error) {
	args := []string{operation}
	if document != "" && operation != "prepare" {
		args = append(args, "--document", document)
	}
	if context != "" {
		args = append(args, "--context", context)
	}
	if operation == "entries" {
		return append(args, "--porcelain"), nil
	}
	guard := r.Guard()
	if context != "" {
		for _, c := range r.Records("comments-context") {
			if c[0] == context {
				guard = c[3]
			}
		}
	}
	if guard == "" {
		return nil, fmt.Errorf("%s", CommentsMissingContext)
	}
	args = append(args, "--expect-context", guard)
	kinds := []string{document}
	if operation == "save" {
		kinds = []string{"local", "shared"}
	}
	if operation == "prepare" {
		kinds = []string{"shared"}
	}
	for _, kind := range kinds {
		revision := "absent"
		for _, d := range r.Documents() {
			if d.Kind == kind && (context == "" || context == d.Context) {
				revision = d.Revision
			}
		}
		if revision == "unreadable" {
			return nil, fmt.Errorf("%s", CommentsUnreadable)
		}
		flag := "--expect-document"
		if operation == "save" {
			flag = "--expect-" + kind
		}
		args = append(args, flag, revision)
	}
	if ordinal > 0 {
		args = append(args, "--entry", strconv.Itoa(ordinal))
	}
	return args, nil
}
