import com.cloudbees.plugins.credentials.Credentials
import com.cloudbees.plugins.credentials.CredentialsNameProvider
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import jenkins.model.Jenkins
import hudson.model.Descriptor

def creds = CredentialsProvider.lookupCredentials(Credentials.class)

println("id,name,kind,description,jobsList")
for (c in creds) {
    def fp = CredentialsProvider.getFingerprintOf(c)
    def jobsList
    try {
        jobsList = fp?.getJobs()
    } catch (Throwable ignored) {
        jobsList = null
    }

    def name = CredentialsNameProvider.name(c) ?: "N/A"
    def type = c?.getClass()?.getSimpleName() ?: "Unknown"
    def kind
    try {
        Descriptor d = Jenkins.instance.getDescriptor(c.class)
        kind = d?.displayName ?: c.class.simpleName
    } catch (ignored) {
        kind = c.class.simpleName
    }
    def description = c?.getDescription() ?: ""

    // Check for unused credentials
    def store = SystemCredentialsProvider.getInstance().getStore()
    if (jobsList == null || jobsList.isEmpty()) {
        //println("REMOVING: ${c.id},${name},${kind},${description},${jobsList}")

        // Attempt to remove from global domain in system credentials store
        def removed = store.removeCredentials(Domain.global(), c)

        println removed ? "Removed ${c.id}" : "Failed to remove ${c.id}"
    }
}
