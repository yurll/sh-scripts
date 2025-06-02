def getDetailsByLabel (label) {
    def details = []
    Jenkins.instance.clouds.each { cloud ->
        if (cloud.class.simpleName == "AmazonEC2Cloud") {
            cloud.getTemplates().each { template ->
                if (template.labelString =~ label) {
                    details << [
                        cloud: cloud.name,
                        label: template.labelString,
                        description: template.description,
                        ami: template.ami,
                        instanceType: template.type
                    ]
                }
            }
        } else if (cloud.class.simpleName =~ "AwsSpotinstCloud") {
            if (cloud.getLabelString() =~ label) {
                details << [
                  cloud: cloud.name,
                  label: cloud.getLabelString()
                ]
            }
        } else if (cloud.class.simpleName == "KubernetesCloud") {
            if (cloud.getLabels() =~ label) {
                details << [
                  cloud: cloud.name,
                  label: cloud.getLabels()]
            }
        } else {
            println "Unknown cloud type: ${cloud.class.simpleName}"
        }
    }
    return details
}

def printDetails(details) {
  println "Details for label '${details.label}':"
    println "  Label: ${details.label}"
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
}

// Example usage
def label = "my-spot-label" // Replace with your label
def detailsList = getDetailsByLabel(label)
detailsList.each { details ->
  printDetails(details)
}
null
