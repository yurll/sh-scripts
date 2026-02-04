import jenkins.model.*
import hudson.plugins.git.*
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition

def createJobFromTemplate(String oldJobName, String prefix, String newBranch) {
    def jenkins = Jenkins.instance

    def oldJob = jenkins.getItemByFullName(oldJobName)
    if (!oldJob) {
        throw new RuntimeException("Job not found: ${oldJobName}")
    }

    def newJobName = "${prefix}-${oldJobName}"

    if (jenkins.getItem(newJobName)) {
        throw new RuntimeException("Job already exists: ${newJobName}")
    }

    // Copy job
    def newJob = jenkins.copy(oldJob, newJobName)

    // ---- Update branch ----
    if (newJob instanceof WorkflowJob) {
        // Pipeline: "Pipeline script from SCM"
        def defn = newJob.getDefinition()
        def scm = defn.getScm()

        scm.branches.clear()
        scm.branches.add(new BranchSpec("*/${newBranch}"))

        def newDef = new CpsScmFlowDefinition(scm, defn.scriptPath)
        newDef.lightweight = defn.lightweight
        newJob.definition = newDef

    } else {
        // Freestyle job
        def scm = newJob.scm
        scm.branches.clear()
        scm.branches.add(new BranchSpec("*/${newBranch}"))
        newJob.scm = scm
    }

    newJob.save()
    jenkins.save()

    println "Created job '${newJobName}' from '${oldJobName}' on branch '${newBranch}'"
}
