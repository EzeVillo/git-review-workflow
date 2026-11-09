package domain

import "strings"

func ParseContinueGuard(output string) string {
	capabilities, guards, value := 0, 0, ""
	for _, line := range strings.Split(strings.ReplaceAll(output, "\r\n", "\n"), "\n") {
		if line == "capability\tcontinue-state" {
			capabilities++
		}
		if strings.HasPrefix(line, "continue-guard\t") {
			guards++
			value = strings.TrimPrefix(line, "continue-guard\t")
		}
	}
	if capabilities == 1 && guards == 1 && stateGuardPattern.MatchString(value) {
		return value
	}
	return ""
}

func ParseContinueReply(output string) (PorcelainResult, bool) {
	lines := strings.Split(strings.TrimSuffix(strings.ReplaceAll(output, "\r\n", "\n"), "\n"), "\n")
	states, markers := 0, 0
	for _, line := range lines {
		if strings.HasPrefix(line, "state\t") {
			states++
		}
		if strings.HasPrefix(line, "continue-state\t") {
			markers++
		}
	}
	if lines[0] != "continue-state\t1" || lines[len(lines)-1] != "continue-state\tcomplete" ||
		states != 1 || markers != 2 || ParseStateGuard(output) == "" {
		return PorcelainResult{}, false
	}
	parsed, ok := ParsePorcelain(output)
	validMode := parsed.State.Mode == ModeWhole || parsed.State.Mode == ModeStep || parsed.State.Mode == ModeWalk
	return parsed, ok && strings.HasPrefix(parsed.State.Branch, "review/") && parsed.Finish == nil && validMode
}
