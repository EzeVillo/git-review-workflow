package domain

import (
	"os"
	"reflect"
	"testing"
)

func TestCommentsSharedFixture(t *testing.T) {
	text, err := os.ReadFile("../../../tests/fixtures/comments/client-records.tsv")
	if err != nil {
		t.Fatal(err)
	}
	r := ParseComments(string(text))
	docs := r.Documents()
	if len(docs) != 4 || docs[0].Count != nil || docs[1].Count == nil || *docs[1].Count != 0 {
		t.Fatalf("documents = %v", docs)
	}
	for _, tag := range []string{"comments-owner", "comments-context", "comments-guard", "comments-document", "comments-count", "comments-diagnostic", "comments-identity", "comments-candidate", "comments-delivery", "comments-capture", "comment-entry", "comment-body", "comment-scope", "comment-version", "comment-path", "comment-location", "comment-unversioned", "comment-diagnostic", "comment-diff", "comment-blob", "comments-delivery-file"} {
		if len(r.Records(tag)) == 0 {
			t.Fatal("missing " + tag)
		}
	}
	if len(r.Records("future-tag")) != 0 {
		t.Fatal("unknown record was not ignored")
	}
	if r.Records("comment-path")[0][2] != "old%2525name" {
		t.Fatal("metadata path was decoded more than once")
	}
}

func TestCommentsIndependentDocuments(t *testing.T) {
	wire := "comments-guard\tstep1\ncomments-context\tc1\treview\tactive\tstep1\tFeature\ncomments-context\tc2\tcompare\tresult\tg2\tOther\ncomments-document\t/l\tc1\tlocal\tpresent\tunreadable\ncomments-document\t/s\tc1\tshared\tabsent\tabsent\textra\ncomments-diagnostic\t/l\tread\tCannot read\ncomments-count\t/s\t0\ncomments-count\t/l\tbad\ncomments-delivery\tc1\tpending\tChanged\nfuture-tag\tignored"
	r := ParseComments(wire)
	if r.Guard() != "step1" {
		t.Fatalf("guard = %q", r.Guard())
	}
	if len(r.Records("comments-context")) != 2 {
		t.Fatal("lost contexts")
	}
	docs := r.Documents()
	if len(docs) != 2 {
		t.Fatalf("documents = %v", docs)
	}
	if docs[0].Count != nil || docs[0].Revision != "unreadable" || docs[1].Count == nil || *docs[1].Count != 0 {
		t.Fatalf("presence/count = %v", docs)
	}
	if r.Records("comments-delivery")[0][1] != "pending" {
		t.Fatal("lost delivery")
	}
}
func TestCommentsPhysicalOrdinal(t *testing.T) {
	r := ParseComments("comment-entry\t2\t7\t12\tSecond\ncomment-entry\t1\t7\t2\tFirst\ncomment-diff\t2\tB1\tH1\ncomment-blob\told\tbase\tpresent\tblob1\ncomment-blob\tnew\thead\tabsent")
	entries := r.Records("comment-entry")
	if len(entries) != 2 || entries[0][0] != "2" || entries[1][0] != "1" {
		t.Fatalf("entries = %v", entries)
	}
	if !reflect.DeepEqual(r.Records("comment-diff")[0], []string{"2", "B1", "H1"}) {
		t.Fatal("wrong immutable range")
	}
	if r.Records("comment-blob")[1][2] != "absent" {
		t.Fatal("absent side lost")
	}
}
