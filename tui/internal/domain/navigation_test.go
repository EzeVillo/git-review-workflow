package domain

import (
	"strings"
	"testing"
)

func TestNavigationReplyRequiresACompleteUnambiguousReport(t *testing.T) {
	reply := "state\treview/x\tx\tdeadbeef\twalk\tapplied\t1\t1\t1\ta.txt\t0\nentry\t1\ta.txt\t0\t1\ncapability\tnavigation-state\nguard\t" + strings.Repeat("a", 40) + "\nnavigation\tunchanged\nnotice\talready at the first entry\n"
	parsed, notice, ok := ParseNavigationReply(reply)
	if !ok || parsed.State.Position != 1 || notice != "already at the first entry" {
		t.Fatalf("bad navigation reply: %#v %q %v", parsed, notice, ok)
	}
	for _, bad := range []string{
		strings.ReplaceAll(reply, "navigation\tunchanged", "navigation\tunknown"),
		strings.ReplaceAll(reply, "capability\tnavigation-state\n", ""),
		strings.ReplaceAll(reply, strings.Repeat("a", 40), "bad"),
		reply + "navigation\tmoved\n",
	} {
		if _, _, ok := ParseNavigationReply(bad); ok {
			t.Fatalf("accepted malformed reply: %q", bad)
		}
	}
}

func TestInlineWhyPreservesBytesAndRejectsIncompleteData(t *testing.T) {
	wire := "why\tpresent\t3\nwhy-line\t1\tcafé \\t \\\\n\nwhy-line\t2\t\nwhy-line\t3\tA\\rB  \n"
	text, ok := ParseInlineWhy(wire)
	if !ok || text != "café \t \\n\n\nA\rB  \n" {
		t.Fatalf("bad decoded prose: %q %v", text, ok)
	}
	if text, ok := ParseInlineWhy("why\tabsent\t0\n"); !ok || text != "" {
		t.Fatal("explicit absent must be known")
	}
	for _, bad := range []string{"", "why\tabsent\t1", "why\tpresent\t0", "why\tpresent\t2\nwhy-line\t1\tone",
		"why\tpresent\t1\nwhy-line\t2\tone", "why\tpresent\t1\nwhy-line\t1\tbad\\x",
		"why\tpresent\t1\nwhy-line\t1\tbad\\", "why\tabsent\t0\nwhy\tabsent\t0"} {
		if _, ok := ParseInlineWhy(bad); ok {
			t.Fatalf("accepted malformed prose %q", bad)
		}
	}
}
