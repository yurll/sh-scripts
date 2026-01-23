import jenkins.model.*

// --- CONFIGURATION ---
def searchString = "1.2.3.4-convert"
def dryRun = true  // Set this to false to ACTUALLY delete the jobs
// ---------------------

def instance = Jenkins.instance
def jobsToDelete = []

println "--- Starting Search for jobs containing '${searchString}' ---"

// Iterate through all items (jobs, folders, etc.) in Jenkins
instance.getAllItems(Job.class).each { job ->
    if (job.name.contains(searchString)) {
        jobsToDelete.add(job)

        if (dryRun) {
            println "[DRY RUN] Found job: '${job.fullName}' - Would be deleted."
        } else {
            try {
                println "[DELETE] Deleting job: '${job.fullName}'..."
                job.delete()
                println "         Successfully deleted."
            } catch (Exception e) {
                println "         ERROR: Could not delete '${job.fullName}'. Reason: ${e.message}"
            }
        }
    }
}

println "--- Finished ---"
if (dryRun && !jobsToDelete.isEmpty()) {
    println "Found ${jobsToDelete.size()} jobs. Change 'dryRun' to false to perform deletion."
} else if (jobsToDelete.isEmpty()) {
    println "No jobs found matching that pattern."
}
