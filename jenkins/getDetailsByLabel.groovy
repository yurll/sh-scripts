def getDetailsByLabel(String label) {
    def details = []

    // Static/permanent Jenkins nodes
    Jenkins.instance.nodes.each { node ->
        def labels = node.getAssignedLabels()*.name ?: []

        if (labels.any { it.contains(label) }) {
            details << [
                type        : 'static',
                name        : node.nodeName,
                label       : node.labelString,
                description : node.nodeDescription,
                remoteFS    : node.remoteFS,
                executors   : node.numExecutors,
                launcher    : node.launcher?.class?.simpleName,
                host        : node.launcher?.hasProperty('host')
                                ? node.launcher.host
                                : null
            ]
        }
    }

    // Dynamically provisioned cloud agents/templates
    Jenkins.instance.clouds.each { cloud ->

        // EC2 Cloud
        if (cloud.class.simpleName == "EC2Cloud") {
            cloud.getTemplates().each { template ->
                def labels = template.labelString?.tokenize() ?: []

                if (labels.any { it.contains(label) }) {
                    details << [
                        type         : 'ec2',
                        cloud        : cloud.name,
                        label        : template.labelString,
                        description  : template.description,
                        ami          : template.ami,
                        instanceType : template.type
                    ]
                }
            }

        // Spotinst Cloud
        } else if (cloud.class.simpleName =~ "AwsSpotinstCloud") {
            def labels = cloud.getLabelString()?.tokenize() ?: []

            if (labels.any { it.contains(label) }) {
                details << [
                    type  : 'spotinst',
                    cloud : cloud.name,
                    label : cloud.getLabelString()
                ]
            }

        // GCP Compute Engine Cloud
        } else if (cloud.class.simpleName == "GcpSpotinstCloud") {

            def labels = cloud.getLabelString()?.tokenize() ?: []

            if (labels.any { it.contains(label) }) {
                details << [
                    type            : 'gcp-spotinst',
                    cloud           : cloud.name,
                    label           : cloud.getLabelString(),
                    elastigroupName : cloud.getElastigroupName(),
                    groupId         : cloud.getGroupId()
                ]
            }

        // Kubernetes Cloud
        } else if (cloud.class.simpleName == "KubernetesCloud") {
            cloud.templates.each { template ->
                def labels = template.label?.tokenize() ?: []

                if (labels.any { it.contains(label) }) {
                    details << [
                        type         : 'kubernetes',
                        cloud        : cloud.name,
                        label        : template.label,
                        templateName : template.name
                    ]
                }
            }
        }
    }

    return details
}

def printDetails(details) {
    println "Details for label '${details.label}':"

    if (details.type) {
        println "  Type: ${details.type}"
    }

    println "  Label: ${details.label}"

    // Static/permanent node
    if (details.name) {
        println "  Node Name: ${details.name}"
    }
    if (details.remoteFS) {
        println "  Remote FS: ${details.remoteFS}"
    }
    if (details.executors != null) {
        println "  Executors: ${details.executors}"
    }
    if (details.launcher) {
        println "  Launcher: ${details.launcher}"
    }
    if (details.host) {
        println "  Host: ${details.host}"
    }

    // Cloud
    if (details.cloud) {
        println "  Cloud: ${details.cloud}"
    }
    if (details.description) {
        println "  Description: ${details.description}"
    }
    if (details.ami) {
        println "  AMI: ${details.ami}"
    }
    if (details.instanceType) {
        println "  Instance Type: ${details.instanceType}"
    }
    if (details.templateName) {
        println "  Template Name: ${details.templateName}"
    }

    println ""
}

// Example usage
def label = "" // Replace with your label
def detailsList = getDetailsByLabel(label)
detailsList.each { details ->
  printDetails(details)
}
null
