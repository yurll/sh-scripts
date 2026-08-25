import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.GitSCM

def targetScriptPath = "JenkinsFiles/myjob.Jenkinsfile"

Jenkins.instance.getAllItems(WorkflowJob.class).each { job ->
    def definition = job.definition

    if (definition instanceof CpsScmFlowDefinition &&
        definition.scriptPath?.contains(targetScriptPath)) {

        def repoUrl = "N/A"

        if (definition.scm instanceof GitSCM) {
            repoUrl = definition.scm.userRemoteConfigs.collect { it.url }.join(", ")
        }

        println "Job: ${job.fullName}"
        println "Repo: ${repoUrl}"
        println "Script Path: ${definition.scriptPath}"
        println "----------------------------------------"
    }
}
