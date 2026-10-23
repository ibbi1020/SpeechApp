/// Root-mean-square of one microphone buffer, on the −1...1 scale.
///
/// Float samples are already on that scale. Int16 samples use the full
/// 16-bit range, so full scale is 32768, not the largest positive code.
public enum SampleLoudness {
    public static func rms(floatSamples: some Sequence<Float>) -> Double {
        meanSquareRoot(floatSamples.lazy.map(Double.init))
    }

    public static func rms(int16Samples: some Sequence<Int16>) -> Double {
        meanSquareRoot(int16Samples.lazy.map { Double($0) / 32_768 })
    }

    private static func meanSquareRoot(_ samples: some Sequence<Double>) -> Double {
        var count = 0
        var sum = 0.0
        for sample in samples {
            sum += sample * sample
            count += 1
        }
        guard count > 0 else { return 0 }
        return (sum / Double(count)).squareRoot()
    }
}
