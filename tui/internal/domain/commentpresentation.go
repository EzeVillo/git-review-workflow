package domain

import (
	"regexp"
	"strconv"
	"strings"
)

type CommentPresentation struct {
	CanOpenDiff                                            bool
	Ordinal                                                int
	Label, Body, Location, Version, Preview, Side, Warning string
	First, Last                                            int
	StartColumn, EndColumn                                 int
}

var commentEscapes = strings.NewReplacer("%25", "%", "%09", "\t", "%0D", "\r", "%0A", "\n", "%3E", ">")
var commentWhitespace = regexp.MustCompile(`\s+`)

func PresentComment(report CommentsReport, entry []string) CommentPresentation {
	rows := func(tag string) [][]string {
		result := [][]string{}
		for _, row := range report.Records(tag) {
			if row[0] == entry[0] {
				result = append(result, row)
			}
		}
		return result
	}
	p := CommentPresentation{Label: entry[1] + ". " + entry[3], Location: CommentsLocationUnavailable}
	p.Ordinal, _ = strconv.Atoi(entry[0])
	lines := []string{}
	for _, row := range rows("comment-body") {
		lines = append(lines, commentEscapes.Replace(row[1]))
	}
	first, last := 0, len(lines)
	for first < last && strings.TrimSpace(lines[first]) == "" {
		first++
	}
	for last > first && strings.TrimSpace(lines[last-1]) == "" {
		last--
	}
	p.Body = strings.Join(lines[first:last], "\n")
	preview := []rune(strings.TrimSpace(commentWhitespace.ReplaceAllString(p.Body, " ")))
	p.Preview = string(preview)
	if len(preview) > 160 {
		p.Preview = string(preview[:159]) + "…"
	}
	if p.Body == "" {
		p.Body = CommentsNoBody
	}
	scope := ""
	for _, row := range rows("comment-scope") {
		scope, p.Side = row[1], row[2]
	}
	for _, row := range rows("comment-location") {
		p.Side = row[1]
		p.First, _ = strconv.Atoi(row[2])
		p.Last, _ = strconv.Atoi(row[3])
	}
	for _, row := range rows("comment-columns") {
		if row[1] == p.Side {
			p.StartColumn, _ = strconv.Atoi(row[2])
			p.EndColumn, _ = strconv.Atoi(row[3])
		}
	}
	if scope == "general" {
		p.Location = CommentsGeneral
	} else {
		for _, row := range rows("comment-path") {
			if row[1] == p.Side {
				suffix := ""
				if p.First > 0 {
					suffix = ":" + strconv.Itoa(p.First) + "–" + strconv.Itoa(p.Last)
					if p.StartColumn > 0 && p.EndColumn > 0 {
						suffix = ":" + strconv.Itoa(p.First) + ":" + strconv.Itoa(p.StartColumn) + "–" + strconv.Itoa(p.Last) + ":" + strconv.Itoa(p.EndColumn)
					}
				}
				side := CommentsHeadSide
				if p.Side == "base" {
					side = CommentsBaseSide
				}
				p.CanOpenDiff = true
				p.Location = commentEscapes.Replace(row[2]) + suffix + " · " + side
			}
		}
	}
	for _, row := range rows("comment-version") {
		p.Version = CommentsOriginalChanges + " · " + row[1][:min(8, len(row[1]))] + " → " + row[2][:min(8, len(row[2]))]
	}
	if len(rows("comment-unversioned")) > 0 {
		p.Warning = CommentsOriginalUnversioned
	}
	title := entry[3]
	for _, row := range rows("comment-path") {
		if row[1] == p.Side && title == commentEscapes.Replace(row[2]) {
			title = ""
			break
		}
	}
	if title == "" || title == p.Location {
		p.Label = entry[1] + ". " + p.Location
	} else {
		p.Label = entry[1] + ". " + title + " · " + p.Location
	}
	return p
}
