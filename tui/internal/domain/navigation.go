package domain

import (
	"strconv"
	"strings"
)

func HasNavigationState(output string) bool {
	count := 0
	for _, line := range strings.Split(output, "\n") {
		if strings.TrimSuffix(line, "\r") == "capability\tnavigation-state" {
			count++
		}
	}
	return count == 1
}

func ParseInlineWhy(output string) (string, bool) {
	var headers, body [][]string
	for _, line := range strings.Split(output, "\n") {
		row := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if row[0] == "why" {
			headers = append(headers, row)
		}
		if row[0] == "why-line" {
			body = append(body, row)
		}
	}
	if len(headers) != 1 || len(headers[0]) != 3 {
		return "", false
	}
	header := headers[0]
	count, err := strconv.Atoi(header[2])
	if err != nil || count < 0 || strconv.Itoa(count) != header[2] {
		return "", false
	}
	if header[1] == "absent" {
		return "", count == 0 && len(body) == 0
	}
	if header[1] != "present" || count == 0 || count != len(body) {
		return "", false
	}
	var result strings.Builder
	for index, row := range body {
		if len(row) != 3 || row[1] != strconv.Itoa(index+1) {
			return "", false
		}
		for at := 0; at < len(row[2]); at++ {
			ch := row[2][at]
			if ch != '\\' {
				result.WriteByte(ch)
				continue
			}
			at++
			if at == len(row[2]) {
				return "", false
			}
			switch row[2][at] {
			case '\\':
				result.WriteByte('\\')
			case 't':
				result.WriteByte('\t')
			case 'r':
				result.WriteByte('\r')
			default:
				return "", false
			}
		}
		result.WriteByte('\n')
	}
	return result.String(), true
}

func ParseNavigationReply(output string) (PorcelainResult, string, bool) {
	var empty PorcelainResult
	states, navigation := 0, 0
	valid := false
	notice := ""
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSuffix(line, "\r")
		if strings.HasPrefix(line, "state\t") {
			states++
		}
		if strings.HasPrefix(line, "navigation\t") {
			navigation++
			valid = line == "navigation\tmoved" || line == "navigation\tunchanged"
		}
		if strings.HasPrefix(line, "notice\t") {
			notice = strings.TrimPrefix(line, "notice\t")
		}
	}
	if states != 1 || navigation != 1 || !valid || !HasNavigationState(output) || ParseStateGuard(output) == "" {
		return empty, "", false
	}
	parsed, ok := ParsePorcelain(output)
	if !ok || !strings.HasPrefix(parsed.State.Branch, "review/") || parsed.Finish != nil ||
		(parsed.State.Mode != ModeWalk && parsed.State.Mode != ModeStep) {
		return empty, "", false
	}
	return parsed, notice, true
}
