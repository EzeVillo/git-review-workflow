package domain

import (
	"strings"
	"testing"
)

func TestSaveReplyRequiresCompleteFinalReports(t *testing.T) {
	wire := "save-state\t1\nstatus\t2\nlist\tbranch\treview-saved/feature\t1\t0\t0\twalk\t2\t3\nconfig\tconfig\tbase\tmain\nconfig\tconfig\tremote\torigin\nsave-state\tcomplete\n"
	if _, ok := ParseSaveReply(wire); !ok {
		t.Fatal("valid response refused")
	}
	if _, ok := ParseSaveReply(strings.ReplaceAll(wire, "\n", "\r\n")); !ok {
		t.Fatal("CRLF response refused")
	}
	for _, bad := range []string{"", strings.ReplaceAll(wire, "save-state\tcomplete\n", ""), wire + "save-state\tcomplete\n",
		strings.ReplaceAll(wire, "status\t2", "status\t0"), strings.ReplaceAll(wire, "list\tbranch", "unknown\tbranch"),
		strings.ReplaceAll(wire, "config\tconfig\tremote\torigin\n", "")} {
		if _, ok := ParseSaveReply(bad); ok {
			t.Fatalf("accepted incomplete response: %q", bad)
		}
	}
}
