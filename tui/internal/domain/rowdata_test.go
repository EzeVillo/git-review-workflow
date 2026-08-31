package domain

import (
	"reflect"
	"testing"
)

func TestFooterFieldAndRowsRoundTrip(t *testing.T) {
	joined := FooterField("feature/x", "1", "0") + "\n" + FooterField("feature/y", "0", "1")
	rows := FooterRows(joined)
	want := [][]string{
		{"feature/x", "1", "0"},
		{"feature/y", "0", "1"},
	}
	if !reflect.DeepEqual(rows, want) {
		t.Fatalf("FooterRows(%q) = %v, want %v", joined, rows, want)
	}
}

func TestFooterRowsEmptyMeansNoRows(t *testing.T) {
	if rows := FooterRows(""); rows != nil {
		t.Fatalf("FooterRows(\"\") = %v, want nil (never one empty row)", rows)
	}
}

func TestBoolCellRoundTrip(t *testing.T) {
	if boolCell(true) != "1" || boolCell(false) != "0" {
		t.Fatal("boolCell must encode true/false as \"1\"/\"0\"")
	}
	if !cellBool("1") || cellBool("0") || cellBool("") {
		t.Fatal("cellBool must decode \"1\" as true and anything else as false")
	}
}
