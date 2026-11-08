package domain

import "strings"

type SaveReply struct{ List, Config string }

func HasSaveState(output string) bool {
	n := 0
	for _, line := range strings.Split(strings.ReplaceAll(output, "\r\n", "\n"), "\n") {
		if line == "capability\tsave-state" {
			n++
		}
	}
	return n == 1
}
func ParseSaveReply(output string) (SaveReply, bool) {
	lines := strings.Split(strings.ReplaceAll(output, "\r\n", "\n"), "\n")
	if lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	if len(lines) < 5 || lines[0] != "save-state\t1" || lines[1] != "status\t2" || lines[len(lines)-1] != "save-state\tcomplete" {
		return SaveReply{}, false
	}
	var list, config []string
	saved, remote := false, 0
	for _, line := range lines[2 : len(lines)-1] {
		if strings.HasPrefix(line, "list\t") && len(config) == 0 {
			row := strings.TrimPrefix(line, "list\t")
			list = append(list, row)
			f := strings.Split(row, "\t")
			if len(f) >= 4 && f[0] == "branch" && f[1] != "" && f[2] == "1" {
				saved = true
			}
		} else if strings.HasPrefix(line, "config\t") {
			row := strings.TrimPrefix(line, "config\t")
			config = append(config, row)
			if strings.HasPrefix(row, "config\tremote\t") {
				remote++
			}
		} else {
			return SaveReply{}, false
		}
	}
	if !saved || remote != 1 {
		return SaveReply{}, false
	}
	return SaveReply{strings.Join(list, "\n") + "\n", strings.Join(config, "\n") + "\n"}, true
}
