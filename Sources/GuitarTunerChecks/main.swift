import Foundation

let runner = CheckRunner()

runNoteMathChecks(runner)
runTuningPresetChecks(runner)
runSignalMetricsChecks(runner)
runPitchDetectorChecks(runner)
runPitchStabilizerChecks(runner)
runRingBufferChecks(runner)
runTunerEvaluatorChecks(runner)
runHarmonicFoldChecks(runner)
runAnalysisProfileChecks(runner)
runSpectrumChecks(runner)
runAdaptiveGateChecks(runner)
runChordChecks(runner)
runSettingsChecks(runner)
runCapoChecks(runner)
runMetronomeChecks(runner)
runToneSynthesizerChecks(runner)
runProgressionChecks(runner)
runHistoryChecks(runner)

exit(runner.report() ? 0 : 1)
