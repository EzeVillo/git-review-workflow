// open.go holds the delegated actions (T089, contracts/cli-invocation.md
// § Herramientas del usuario): file paths go through $EDITOR, previewEdits
// runs `git review preview` with an inherited terminal, and external links go
// through the operating system's browser opener. None of the *Cmd builders
// here run anything themselves — each returns a plain *exec.Cmd for
// internal/ui to hand to tea.ExecProcess, which is what actually suspends the
// program, gives the child the real TTY, and resumes it when the child exits
// (internal/ui/mutation.go).
package host

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// splitShellWords splits s using POSIX shell word-splitting rules — single
// quotes (literal, no escapes inside), double quotes (only \\, \", \$, \`
// are escapes inside, matching POSIX; every other backslash inside a
// double-quoted section is literal), and backslash escapes outside quotes.
// A plain strings.Fields split works by coincidence for an unquoted
// EDITOR="code -w" and breaks the moment a quoted argument carries a space
// itself (research.md Decisión 12): $EDITOR carrying arguments is common
// enough (code -w, nvim -R) that this cannot be skipped.
func splitShellWords(s string) ([]string, error) {
	var (
		words  []string
		cur    strings.Builder
		hasCur bool
	)
	const (
		bare = iota
		single
		double
	)
	state := bare
	runes := []rune(s)
	for i := 0; i < len(runes); i++ {
		r := runes[i]
		switch state {
		case bare:
			switch {
			case r == '\'':
				state = single
				hasCur = true
			case r == '"':
				state = double
				hasCur = true
			case r == '\\':
				if i+1 >= len(runes) {
					return nil, errors.New("trailing backslash")
				}
				i++
				cur.WriteRune(runes[i])
				hasCur = true
			case r == ' ' || r == '\t' || r == '\n':
				if hasCur {
					words = append(words, cur.String())
					cur.Reset()
					hasCur = false
				}
			default:
				cur.WriteRune(r)
				hasCur = true
			}
		case single:
			if r == '\'' {
				state = bare
			} else {
				cur.WriteRune(r)
			}
		case double:
			switch {
			case r == '"':
				state = bare
			case r == '\\' && i+1 < len(runes) && strings.ContainsRune(`"\$`+"`", runes[i+1]):
				i++
				cur.WriteRune(runes[i])
			default:
				cur.WriteRune(r)
			}
		}
	}
	if state != bare {
		return nil, errors.New("unterminated quote")
	}
	if hasCur {
		words = append(words, cur.String())
	}
	return words, nil
}

// EditorArgv resolves $EDITOR into an argv via splitShellWords. ok=false
// when $EDITOR is unset/blank or fails to parse (an unterminated quote) —
// never a fallback to vi/nano: this client only ever runs the editor the
// reviewer actually configured.
func EditorArgv() (argv []string, ok bool) {
	raw := strings.TrimSpace(os.Getenv("EDITOR"))
	if raw == "" {
		return nil, false
	}
	words, err := splitShellWords(raw)
	if err != nil || len(words) == 0 {
		return nil, false
	}
	return words, true
}

// OpenInEditorCmd builds openEntry/openChange's own command: $EDITOR with
// `display` appended (the entry's DISPLAY path — CLAUDE.md's rule that Raw
// never reaches a tool), rooted at dir. ok=false means nothing to run; reason
// names WHAT did not happen ("no editor is configured", "the editor was not
// found") rather than a raw exec error, per FR-024 and research.md Decisión
// 12: these fallbacks are the ONLY case that shows, and they show only
// because there is genuinely no stderr from any process to show instead.
func OpenInEditorCmd(display, dir string) (cmd *exec.Cmd, reason string, ok bool) {
	argv, ok := EditorArgv()
	if !ok {
		return nil, "No editor is configured: set $EDITOR and try again.", false
	}
	editorPath, err := exec.LookPath(argv[0])
	if err != nil {
		return nil, fmt.Sprintf("The configured editor (%s) was not found.", argv[0]), false
	}
	args := make([]string, 0, len(argv)-1+1)
	args = append(args, argv[1:]...)
	args = append(args, display)
	c := exec.Command(editorPath, args...)
	c.Dir = dir
	return c, "", true
}

// DiffPathCmd builds openChange's own command for a single file (walk
// mode): `git -c core.quotePath=false diff HEAD -- <display>`, rooted at
// dir. HEAD on a review/* branch is pinned at the merge-base, so this is
// exactly the PR's own change to this one file plus whatever the reviewer
// has since edited — the same comparison finish itself extracts, without
// previewEdits' throwaway-tree machinery a single file never needs.
// Stdin/Stdout/Stderr are left unset on purpose: tea.ExecProcess wires them
// to the real terminal itself (internal/ui/mutation.go), which is what lets
// git decide color and paging exactly as it would running by hand.
func DiffPathCmd(display, dir string) *exec.Cmd {
	c := exec.Command("git", "-c", "core.quotePath=false", "diff", "HEAD", "--", display)
	c.Dir = dir
	return c
}

// DiffCommitCmd is openChange's step-mode shape: the WHOLE commit's own
// change, since step has no single path to name for its "Diff" control.
func DiffCommitCmd(sha, dir string) *exec.Cmd {
	c := exec.Command("git", "-c", "core.quotePath=false", "diff", sha+"^", sha)
	c.Dir = dir
	return c
}

// OpenURLCmd delegates an allowlisted web address to the native browser
// launcher. Like the editor and diff helpers above, it only builds the child
// command; ui hands it to tea.ExecProcess so the terminal remains coherent
// while the launcher runs.
func OpenURLCmd(url string) *exec.Cmd {
	switch runtime.GOOS {
	case "windows":
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	case "darwin":
		return exec.Command("open", url)
	default:
		return exec.Command("xdg-open", url)
	}
}
