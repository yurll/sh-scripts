import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.jenkins.plugins.awscredentials.AWSCredentialsImpl
import com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey
import org.jenkinsci.plugins.plaincredentials.impl.*
import jenkins.model.*
import hudson.util.Secret
import groovy.json.JsonOutput

// Set to true to write to file, false to print
def BACKUP = false

def creds = CredentialsProvider.lookupCredentials(
    Credentials.class,
    Jenkins.instance,
    null,
    null
)

def results = []

for (c in creds) {
    def entry = [
        id         : c.id,
        description: c.description,
        className  : c.getClass().getName()
    ]

    if (c instanceof UsernamePasswordCredentialsImpl) {
        entry.type     = "UsernamePassword"
        entry.username = c.username
        entry.password = Secret.toString(c.password)
    } else if (c instanceof StringCredentialsImpl) {
        entry.type   = "String"
        entry.secret = Secret.toString(c.secret)
    } else if (c instanceof BasicSSHUserPrivateKey) {
        entry.type       = "SSH"
        entry.username   = c.username
        entry.privateKey = c.privateKey
        entry.passphrase = c.passphrase?.getPlainText()
    } else if (c instanceof FileCredentialsImpl) {
        entry.type     = "File"
        entry.fileName = c.fileName
    } else if (c instanceof AWSCredentialsImpl) {
        entry.type      = "AWS"
        entry.accessKey = c.accessKey
        entry.secretKey = c.secretKey?.getPlainText()
    } else if (c instanceof io.snyk.jenkins.credentials.DefaultSnykApiToken) {
        entry.type  = "Snyk"
        entry.token = c.token?.getPlainText()
    } else {
        entry.type = "UNKNOWN"
    }

    results << entry
}

// Output logic
if (BACKUP) {
    def timestamp = new Date().format("yyyyMMdd-HHmmss")
    def path = "/var/lib/jenkins/credentials-backup-${timestamp}.json"
    def file = new File(path)
    file.text = JsonOutput.prettyPrint(JsonOutput.toJson(results))
    println "Credentials backup saved to: ${path}"
} else {
    results.each { cred ->
        println "ID: ${cred.id}"
        println "Description: ${cred.description}"
        println "Type: ${cred.type}"
        println "Class: ${cred.className}"
        cred.each { k, v ->
            if (!["id", "description", "type", "className"].contains(k)) {
                println "${k}: ${v}"
            }
        }
        println "---"
    }
}
