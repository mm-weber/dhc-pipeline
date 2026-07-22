package checks

import batchv1 "k8s.io/api/batch/v1"

// JobSucceeded reports whether job has completed successfully (used to wait on
// the in-cluster HTTP probe Jobs).
func JobSucceeded(job *batchv1.Job) bool { return job.Status.Succeeded > 0 }
