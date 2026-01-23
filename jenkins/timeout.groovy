// Pause the pipeline for manual intervention or timeout after a specified duration
def timeoutWithContinue(int timeoutDuration = 30, String timeoutUnit = 'MINUTES') {
    script {
        try {
            timeout(time: timeoutDuration, unit: timeoutUnit) {
                input message: "[DEBUG] Pause: click 'Proceed' to continue manually, or wait ${timeoutDuration} ${timeoutUnit.toLowerCase()} to auto-continue."
            }
        } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
            echo '[DEBUG] Continuing automatically...'
        }
    }
}
