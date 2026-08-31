// Package domain is the TUI's pure core: porcelain parsing, situation
// derivation, the panel projection, copy, the confirmation table, the icon
// map and the keymap. Nothing here touches a terminal, a filesystem or a
// process (FR-045) — see purity_test.go and module_boundary_test.go, which
// hold that line by parsing imports rather than trusting a comment.
package domain

import "strconv"

// PathRef carries the two forms a path takes once it crosses the porcelain
// boundary (data-model.md § PathRef).
//
//   - Raw is exactly what porcelain emitted: the only form that goes back to
//     the CLI (`status --why <raw>`).
//   - Display is the de-quoted, human form: the only form that goes to the
//     screen, to $EDITOR and to any stat().
//
// NEVER send Display to the CLI, and NEVER send Raw to the screen. This
// matters more here than in the other three clients because the same string
// passes through a terminal, which will not forgive a stray C-quote escape
// the way a diff view might. PathRef does not enforce the rule at runtime —
// see pathref_test.go for why that is a deliberate, documented choice — it
// is enforced by never having a second way to read either field.
type PathRef struct {
	Raw     string
	Display string
}

// NewPathRef builds a PathRef from what porcelain printed, unquoting it for
// Display.
func NewPathRef(raw string) PathRef {
	return PathRef{Raw: raw, Display: UnquotePath(raw)}
}

// UnquotePath undoes the C-style quoting git applies to a path when it
// contains a `"` or a `\` byte — which git still does even under
// `core.quotePath=false` (research.md Decision 8; mirrors
// vscode-extension/src/cli/unquote.ts, jetbrains-plugin's and
// visualstudio-extension's equivalents: same field, fourth parser). A raw
// value that is not wrapped in a leading and trailing `"` was never quoted
// and passes through unchanged. The operation is one-directional: the
// result is never re-quoted anywhere in this client.
func UnquotePath(raw string) string {
	if len(raw) < 2 || raw[0] != '"' || raw[len(raw)-1] != '"' {
		return raw
	}
	inner := raw[1 : len(raw)-1]
	out := make([]byte, 0, len(inner))
	for i := 0; i < len(inner); {
		ch := inner[i]
		if ch != '\\' || i+1 >= len(inner) {
			out = append(out, ch)
			i++
			continue
		}
		next := inner[i+1]
		if isOctalDigit(next) && i+4 <= len(inner) && isOctalDigit(inner[i+2]) && isOctalDigit(inner[i+3]) {
			// Three consecutive octal escapes decode to three raw bytes of a
			// multi-byte UTF-8 sequence; appending each byte in order and
			// letting `string(out)` wrap the buffer at the end reassembles
			// it without any separate codepoint-decoding step.
			n, err := strconv.ParseUint(inner[i+1:i+4], 8, 8)
			if err == nil {
				out = append(out, byte(n))
				i += 4
				continue
			}
		}
		var decoded byte
		switch next {
		case '\\':
			decoded = '\\'
		case '"':
			decoded = '"'
		case 'a':
			decoded = '\a'
		case 'b':
			decoded = '\b'
		case 'f':
			decoded = '\f'
		case 'n':
			decoded = '\n'
		case 'r':
			decoded = '\r'
		case 't':
			decoded = '\t'
		case 'v':
			decoded = '\v'
		default:
			decoded = next
		}
		out = append(out, decoded)
		i += 2
	}
	return string(out)
}

func isOctalDigit(b byte) bool { return b >= '0' && b <= '7' }
