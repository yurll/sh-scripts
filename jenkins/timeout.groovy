// Pause the pipeline for manual intervention or timeout after a specified duration
def timeoutWithContinue(String text = '', int timeoutDuration = 30, boolean autoContinue = false, String timeoutUnit = 'MINUTES') {
    script {
        try {
            timeout(time: timeoutDuration, unit: timeoutUnit) {
                input message: "[DEBUG] ${text}: click 'Proceed' to continue manually, or wait ${timeoutDuration} ${timeoutUnit.toLowerCase()} to auto-continue."
            }
        } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
            if (autoContinue) {
                echo '[DEBUG] Continuing automatically...'
            } else {
                throw e
            }
        }
    }
}
