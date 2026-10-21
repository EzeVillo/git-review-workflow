package ui

import (
	"encoding/base64"
	"fmt"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
)

func TestCopyCommentPathUsesOnlyTheReportedLocalPathWithoutLaunchingCommands(t *testing.T) {
	const path = "C:/repo with spaces/.git/review-comments/results/c/g/local-ñ.md"
	var wire string
	restore := host.SetOSC52WriterForTest(func(s string) { wire = s })
	defer restore()
	for _, kind := range []string{"review", "compare"} {
		for _, state := range []string{"active", "result", "repository"} {
			m := Model{Panel: domain.PanelModel{Comments: fmt.Sprintf("comments-context\tc\t%s\t%s\tg\tFeature\ncomments-document\t/absent\tc\tlocal\tabsent\tabsent\ncomments-document\t%s\tc\tlocal\tpresent\tunreadable\ncomments-document\t/shared\tc\tshared\tpresent\ts", kind, state, path)}}
			var copies []Control
			for _, c := range commentsControls(m.Panel) {
				if c.ID == "copyCommentPath" {
					copies = append(copies, c)
				}
			}
			if len(copies) != 1 || copies[0].Variant != "1" || !copies[0].Enabled {
				t.Fatalf("%s/%s: copy controls = %+v", kind, state, copies)
			}
			for _, invalid := range []string{"0", "2", "-1", "3", "unknown"} {
				wire = ""
				after, cmd := m.activateControl("copyCommentPath", invalid)
				if cmd != nil || wire != "" || after.statusLine != "" || after.confirm != nil {
					t.Fatalf("%s/%s: invalid document %q copied or dispatched work", kind, state, invalid)
				}
			}
			after, cmd := m.activateControl("copyCommentPath", "1")
			if cmd != nil || after.confirm != nil || after.statusLine != domain.CommentsPathCopySent || after.Panel.Comments != m.Panel.Comments {
				t.Fatal("copy must only write OSC 52 and acknowledge it")
			}
			payload := strings.TrimSuffix(strings.TrimPrefix(wire, "\x1b]52;c;"), "\x07")
			decoded, err := base64.StdEncoding.DecodeString(payload)
			if err != nil || string(decoded) != path {
				t.Fatalf("clipboard = %q, %v; want %q", decoded, err, path)
			}
			m.Panel.Busy = true
			for _, c := range commentsControls(m.Panel) {
				if c.ID == "copyCommentPath" && c.Enabled {
					t.Fatal("copy must be disabled while the panel is busy")
				}
			}
		}
	}
}
