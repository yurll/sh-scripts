import com.cloudbees.plugins.credentials.Credentials;
import com.cloudbees.plugins.credentials.CredentialsNameProvider;
import com.cloudbees.plugins.credentials.CredentialsProvider;

def creds = CredentialsProvider.lookupCredentials(
      Credentials.class
);
println("id,name,kind,description,jobsList");
for (c in creds) {
  fp = CredentialsProvider.getFingerprintOf(c);
  try {
    jobsList = fp.getJobs();
  } catch (Throwable ignored) {
        jobsList = "N/A"
    }
  def name = CredentialsNameProvider.name(c) ?: "N/A"
  def type = c?.getClass()?.getSimpleName() ?: "Unknown"
  try {
        Descriptor d = Jenkins.instance.getDescriptor(c.class)
        kind = d?.displayName ?: c.class.simpleName
    } catch (ignored) {
        kind = c.class.simpleName
    }
  def description = c?.getDescription() ?: ""
  println("${c.id},${name},${kind},${description},${jobsList}");
}
