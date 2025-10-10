@NonCPS
def getCauser() {
    def cause = currentBuild.rawBuild.getCause(hudson.model.Cause$UpstreamCause)
    if (!cause) {
        return null
    }
    return [
        shortDescription: cause.shortDescription,
        upstreamBuild   : cause.upstreamBuild,
        upstreamUrl     : cause.upstreamUrl,
        upstreamProject : cause.upstreamProject
    ]
}
