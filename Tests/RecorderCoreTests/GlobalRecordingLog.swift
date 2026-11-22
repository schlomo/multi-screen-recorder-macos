import Testing

/// Every suite that sets or reads the process-global recording log
/// (`RecorderLog.recording`, or a `Recorder` run, which sets it at its start and
/// resets it at its stop) nests here: they run one after another, as two
/// running at once would replace each other's log.
@Suite(.serialized) enum GlobalRecordingLog {}
