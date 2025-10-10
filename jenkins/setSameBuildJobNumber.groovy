import jenkins.model.*

Jenkins.instance.items.findAll { job -> job.name.endsWith("-some-job-OLD") }.each { oldJob ->
    def baseJobName = oldJob.name.replaceAll(/-OLD$/, "")
    def baseJob = Jenkins.instance.getItem(baseJobName)

    if (baseJob) {
        def lastBuild = oldJob.getLastBuild()
        if (lastBuild) {
            def newBuildNumber = lastBuild.number + 1
            println "Setting next build number for ${baseJob.name} to ${newBuildNumber}"

            try {
                baseJob.updateNextBuildNumber(newBuildNumber)
                //println "pass"
            } catch (Exception e) {
                println "Failed to update next build number for ${baseJob.name}: ${e.message}"
            }
        } else {
            println "No builds found for ${oldJob.name}, skipping..."
        }
    } else {
        println "No matching job found for ${oldJob.name}, skipping..."
    }
}
