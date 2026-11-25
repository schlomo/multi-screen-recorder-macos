/// The audio half's values (*data*, D45, D46): starting points, calibrated
/// at the v1 gate, beside `RecorderValues`; the bit rates
/// are in `Encoding`.
extension RecorderValues {
    /// Every audio file's sample rate; every audio input measured ran at it.
    public static let audioSampleRate = 48_000
    /// How far a buffer's timestamp may run ahead of the position its sample
    /// count gives before it is a gap: above one buffer of 512 samples
    /// (about 10.7 ms), so ordinary jitter is no gap.
    public static let audioGapTolerance = Duration.milliseconds(32)
    /// The longest gap filled with silence; a longer one ends the audio
    /// file and a new one starts (D46).
    public static let longestFilledAudioGap = Duration.seconds(1)
    /// How far behind real time the guide tracks are mixed, so every
    /// source's buffers have arrived, also those of an input placed up to
    /// `guideTrackSyncLimit` earlier by its audio delay (D80).
    public static let guideTrackDelay = Duration.seconds(1)
    /// How long an input moved in "Audio inputs" fades from where it was
    /// placed to where it is placed now (D80).
    public static let guideTrackCrossfade = Duration.milliseconds(20)
    /// How often the guide tracks are mixed and handed to the screen files.
    public static let guideTrackInterval = Duration.milliseconds(100)
    /// How much audio an audio file's writer takes in one append, about
    /// 100 ms as the guide tracks: one append per buffer of 512 samples cost
    /// more than the encoder, and a crash loses up to this much more.
    public static let audioFileAppendSamples = audioSampleRate / 10
    /// How often the CPU use of our process is sampled.
    public static let cpuSampleInterval = Duration.seconds(1)
}

/// The level meters, the input volume and no audio (D69).
extension RecorderValues {
    /// The level meter's scale: from this many dBFS up to 0 dBFS.
    public static let levelMeterFloorDBFS = -60.0
    /// A level meter is red from this many dBFS on.
    public static let levelMeterRedDBFS = -1.0
    /// How long a level meter holds its highest peak.
    public static let levelMeterPeakHold = Duration.milliseconds(1500)
    /// How often the status window draws the level meters and the input
    /// volume while it is open.
    public static let levelMeterInterval = Duration.milliseconds(100)
    /// How long an input volume must hold still before its change is the
    /// event `audio input volume changed`.
    public static let inputVolumeSettleTime = Duration.milliseconds(500)
    /// How often the recorder reads the input volume, for a change that
    /// Core Audio does not report to its listener.
    public static let inputVolumeReadInterval = Duration.milliseconds(250)
    /// How long an audio input must deliver exact zeros before it has no
    /// audio and its audio file ends.
    public static let noAudioTime = Duration.seconds(10)
    /// No audio whose zeros began this soon after a gap of the same input
    /// is the input broken by the gap, a problem (D81).
    public static let silenceAfterGapsTime = Duration.seconds(10)
}

/// An audio input file's audio delay (D80): set at its first counted
/// window, set once more at `AudioDelay.windowsNeeded` to their median,
/// then changed only by the median of the counted windows of the latest
/// `audioDelayChangeWindowSeconds`, at least `audioDelayChangeWindows` of
/// them, each time only beyond `audioDelayTolerance`. A file not in the
/// guide track yet whose window had sound in
/// `audioDelayUnclearMeasurements` measurements without counting has no
/// clear sound to sync.
extension RecorderValues {
    public static let audioDelayUnclearMeasurements = 3
    /// The measurements in a row without a counted window against the reference, while another input has
    /// sound, after which the reference moves (D89).
    public static let referenceUnsyncedMeasurements = 3
    /// An action score (D89) is the spread of a window's slices' levels, each slice this long: the level of
    /// `actionScoreHighPercentile` of them less that of `actionScoreLowPercentile`, in dB.
    public static let actionScoreSlice = Duration.milliseconds(100)
    public static let actionScoreLowPercentile = 0.1
    public static let actionScoreHighPercentile = 0.9
    /// Action scores this close to the highest are a tie: the reference in use stays, else the lowest number.
    public static let actionScoreTie = 3.0
    public static let audioDelayChangeWindowSeconds = 60.0
    public static let audioDelayChangeWindows = 5
    /// One frame at 30 fps: closer than this, a new median changes nothing.
    public static let audioDelayTolerance = 1.0 / Double(framesPerSecond)
}

/// The clock drift correction's values (*data*): the intervals the
/// buffers' lateness is measured in, the support line through them, the
/// rate that follows it, and the clock drift shown.
extension RecorderValues {
    /// Buffers are grouped by arrival in intervals of this length; each
    /// interval with a buffer gives a point, its smallest lateness.
    public static let clockDriftInterval = Duration.seconds(1)
    /// Points older than this are dropped: the support line is laid under
    /// the points of the last 20 s.
    public static let clockDriftHorizon = Duration.seconds(20)
    /// An estimate needs at least this many points, spanning at least this long.
    public static let clockDriftEstimateMinimumPoints = 5
    public static let clockDriftEstimateMinimumSpan = Duration.seconds(10)
    /// What is still off is caught up over this long, on top of the line's
    /// slope; without a fresh estimate the rate holds for this long, then
    /// is the kept slope.
    public static let clockDriftCatchUpTime = Duration.seconds(10)
    /// The largest correction rate and the steepest support line, in parts per million.
    public static let clockDriftMaximumRatePpm = 1000.0
    /// The kept slope is the median slope of this many estimates at most:
    /// the clock drift shown (from this many estimates on), a gap's drift,
    /// and the rate after the hold.
    public static let clockDriftShownEstimates = 60
    public static let clockDriftShownMinimumEstimates = 10
    /// How often an audio capture reports its clock drift to the status window.
    public static let clockDriftStatusInterval = Duration.seconds(1)
    /// How often the recording log, and with `--debug` standard error, get the clock drift block of all audio sources.
    public static let clockDriftDetailInterval = Duration.seconds(10)
    /// The resampler's filter: taps, phases between two samples, and its
    /// cutoff as a fraction of the sample rate.
    public static let clockDriftResamplerTaps = 64
    public static let clockDriftResamplerPhases = 512
    public static let clockDriftResamplerCutoff = 0.45
    public static let clockDriftResamplerKaiserBeta = 9.0
}

