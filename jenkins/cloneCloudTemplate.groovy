import java.lang.reflect.Field
import jenkins.model.Jenkins
import org.csanchez.jenkins.plugins.kubernetes.KubernetesCloud
import org.csanchez.jenkins.plugins.kubernetes.PodTemplate

// =========== CONFIGURARION ===========
def cloudName       = "kubernetes"          // Jenkins cloud name
def sourceName      = "existing-template"   // existing Pod Template Name
def newTemplateName = "new-template-name"   // new Pod Template Name
def newLabel        = "new-template-label"  // new Pod Template Label
// =====================================

def j = Jenkins.get()
def cloud = j.clouds.getByName(cloudName)

if (!(cloud instanceof KubernetesCloud)) {
    throw new IllegalStateException("Cloud '${cloudName}' not found or is not a KubernetesCloud")
}

def source = cloud.templates.find { it.name == sourceName }
if (source == null) {
    throw new IllegalStateException("Template with name '${sourceName}' not found in cloud '${cloudName}'")
}

if (cloud.templates.any { it.name == newTemplateName }) {
    throw new IllegalStateException("A template with name '${newTemplateName}' already exists")
}

if (cloud.templates.any { it.label == newLabel }) {
    throw new IllegalStateException("A template with label '${newLabel}' already exists")
}

def cloned = new PodTemplate(source)
Field idField = PodTemplate.class.getDeclaredField("id")
idField.setAccessible(true)
idField.set(cloned, UUID.randomUUID().toString())

cloned.setName(newTemplateName)
cloned.setLabel(newLabel)

cloud.addTemplate(cloned)
j.save()

println "Created new Kubernetes pod template successfully."
println "Cloud        : ${cloudName}"
println "Source name  : ${source.name}"
println "New name     : ${cloned.name}"
println "New label    : ${cloned.label}"
println "New id       : ${cloned.id}"
