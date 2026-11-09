package domain

import (
	"strings"
	"testing"
)

func TestContinueReplyRequiresCompleteAuthoritativeState(t *testing.T) {
	guard := strings.Repeat("a", 40)
	body := "state\treview/feature\tfeature\tdeadbeef\twhole\tnone\nguard\t" + guard + "\n"
	wire := "continue-state\t1\n" + body + "continue-state\tcomplete\n"
	if _, ok := ParseContinueReply(wire); !ok {
		t.Fatal("valid reply rejected")
	}
	if _, ok := ParseContinueReply(strings.ReplaceAll(wire, "\n", "\r\n")); !ok {
		t.Fatal("CRLF reply rejected")
	}
	for _, bad := range []string{"", body, strings.ReplaceAll(wire, "continue-state\tcomplete\n", ""), wire + "continue-state\tcomplete\n", strings.ReplaceAll(wire, body, body+body), strings.ReplaceAll(wire, "review/feature", "main")} {
		if _, ok := ParseContinueReply(bad); ok {
			t.Fatalf("accepted malformed reply: %q", bad)
		}
	}
}

func TestContinueInventoryRequiresCapabilityAndOneValidToken(t *testing.T) {
	guard := strings.Repeat("a", 40)
	wire := "capability\tcontinue-state\ncontinue-guard\t" + guard + "\n"
	if ParseContinueGuard(wire) != guard {
		t.Fatal("valid token rejected")
	}
	for _, bad := range []string{"", wire + wire, strings.ReplaceAll(wire, guard, "bad"), strings.ReplaceAll(wire, guard, guard+" "), strings.ReplaceAll(wire, "capability\tcontinue-state\n", "")} {
		if ParseContinueGuard(bad) != "" {
			t.Fatalf("accepted ambiguous token: %q", bad)
		}
	}
	a := StateToken{ContinueGuard: guard, Situation: SituationNoReview}
	if a.Matches(StateToken{ContinueGuard: strings.Repeat("b", 40), Situation: SituationNoReview}) {
		t.Fatal("changed inventory accepted")
	}
}
