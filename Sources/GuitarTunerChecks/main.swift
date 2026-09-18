import Foundation

let runner = CheckRunner()

runNoteMathChecks(runner)
runTuningPresetChecks(runner)
runSignalMetricsChecks(runner)
runPitchDetectorChecks(runner)
runPitchStabilizerChecks(runner)
runRingBufferChecks(runner)
runTunerEvaluatorChecks(runner)
runAnalysisProfileChecks(runner)
runSpectrumChecks(runner)
runAdaptiveGateChecks(runner)

exit(runner.report() ? 0 : 1)
