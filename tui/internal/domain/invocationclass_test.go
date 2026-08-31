package domain

import "testing"

func TestClassForVerbTimeouts(t *testing.T) {
	cases := []struct {
		verb string
		args []string
		want InvocationClass
	}{
		{"status", []string{"--porcelain"}, Read},
		{"list", []string{"--porcelain"}, Read},
		{"--version", nil, Read},
		{"start", []string{"--", "feature"}, Network},
		{"finish", []string{"--abort"}, LocalMutation},
		{"save", nil, LocalMutation},
		{"abort", nil, LocalMutation},
		{"continue", []string{"feature"}, LocalMutation},
		{"next", nil, LocalMutation},
		{"prev", nil, LocalMutation},
		{"clean", []string{"feature"}, LocalMutation},
		{"compare", []string{"--", "a", "b"}, LocalMutation},
		{"walkthrough", []string{"build"}, LocalMutation},
		{"preview", nil, LocalMutation},
		{"forget", []string{"--saved", "feature"}, LocalMutation},
		{"forget", []string{"--delta", "--stale"}, Network},
		{"some-future-verb", nil, Read},
	}
	for _, c := range cases {
		if got := ClassForVerb(c.verb, c.args); got != c.want {
			t.Errorf("ClassForVerb(%q, %v) = %v, want %v", c.verb, c.args, got, c.want)
		}
	}
}

// config base|remote is a config WRITE, not a ref move, so it stays Read —
// the same rule the other three clients use, and its own explicit gate per
// T033.
func TestConfigBaseOrRemoteIsRead(t *testing.T) {
	if got := ClassForVerb("config", []string{"base", "--", "develop"}); got != Read {
		t.Errorf("config base = %v, want Read", got)
	}
	if got := ClassForVerb("config", []string{"remote", "--", "origin"}); got != Read {
		t.Errorf("config remote = %v, want Read", got)
	}
}

func TestTimeoutMillis(t *testing.T) {
	cases := map[InvocationClass]int{
		Read: 15000, LocalMutation: 120000, Network: 300000, SupportGit: 30000,
	}
	for class, want := range cases {
		if got := class.TimeoutMillis(); got != want {
			t.Errorf("%v.TimeoutMillis() = %d, want %d", class, got, want)
		}
	}
}
