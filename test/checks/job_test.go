package checks

import (
	"testing"

	batchv1 "k8s.io/api/batch/v1"
)

// TestJobSucceeded exercises the Job-completion predicate the e2e specs use to
// wait on the in-cluster HTTP probe Jobs: succeeded iff Status.Succeeded > 0
// (Req 5.5).
func TestJobSucceeded(t *testing.T) {
	cases := []struct {
		name string
		job  *batchv1.Job
		want bool
	}{
		{
			name: "one succeeded",
			job:  &batchv1.Job{Status: batchv1.JobStatus{Succeeded: 1}},
			want: true,
		},
		{
			name: "none succeeded",
			job:  &batchv1.Job{Status: batchv1.JobStatus{Succeeded: 0}},
			want: false,
		},
		{
			name: "failed only",
			job:  &batchv1.Job{Status: batchv1.JobStatus{Succeeded: 0, Failed: 3}},
			want: false,
		},
		{
			name: "zero value",
			job:  &batchv1.Job{},
			want: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := JobSucceeded(tc.job); got != tc.want {
				t.Errorf("JobSucceeded() = %v, want %v", got, tc.want)
			}
		})
	}
}
