import jenkins.model.*

def job_exceptions_list = ["this_job_should_not_be_deleted"]
def force_delete_jobs_list = ["this_job_should_be_deleted"]
def matchedJobs = Jenkins.instance.items.findAll { job ->
	job.name =~ /^(my-jobs-to-remove-.*)$/ &&
    !job_exceptions_list.any { exception -> job.name.contains(exception) } ||
      force_delete_jobs_list.any { explicit -> job.name == explicit }
}

matchedJobs.each() { job ->
  println "Removing ${job.name}"
  // job.delete()
}
null
