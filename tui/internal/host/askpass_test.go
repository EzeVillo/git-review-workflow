package host

import (
	"os"
	"strings"
	"testing"
)

func TestIsAskpassSentinel(t *testing.T) {
	t.Setenv(AskpassSentinelEnv, "")
	if IsAskpassSentinel() {
		t.Fatal("expected false with the sentinel unset")
	}
	t.Setenv(AskpassSentinelEnv, "1")
	if !IsAskpassSentinel() {
		t.Fatal("expected true with the sentinel set to 1")
	}
}

func TestNetworkEnvCarriesTerminalPromptOffAndAskpass(t *testing.T) {
	env := networkEnv()
	joined := strings.Join(env, "\n")
	if !strings.Contains(joined, "GIT_TERMINAL_PROMPT=0") {
		t.Fatalf("networkEnv() = %v, missing GIT_TERMINAL_PROMPT=0", env)
	}
	self, err := os.Executable()
	if err != nil {
		t.Skip("os.Executable unavailable in this environment")
	}
	if !strings.Contains(joined, "GIT_ASKPASS="+self) {
		t.Errorf("networkEnv() = %v, missing GIT_ASKPASS pointing at %s", env, self)
	}
	if !strings.Contains(joined, "SSH_ASKPASS="+self) {
		t.Errorf("networkEnv() = %v, missing SSH_ASKPASS pointing at %s", env, self)
	}
	if !strings.Contains(joined, AskpassSentinelEnv+"=1") {
		t.Errorf("networkEnv() = %v, missing the sentinel", env)
	}
}
