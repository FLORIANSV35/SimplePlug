#pragma once

#include <juce_audio_devices/juce_audio_devices.h>
#include <atomic>

/** Wraps an AudioIODeviceCallback and measures its load: compute time / buffer duration
    (1.0 = 100 % = dropout). Written by the audio thread, read by the UI. */
class MeteredCallback final : public juce::AudioIODeviceCallback
{
public:
    explicit MeteredCallback (juce::AudioIODeviceCallback& targetToWrap) : target (targetToWrap) {}

    struct Reading
    {
        double average = 0.0, peak = 0.0;
        bool valid = false;
    };

    /** Average and peak load since the previous read (UI thread). */
    Reading read()
    {
        const auto count = loadCount.load (std::memory_order_relaxed);
        const auto sum   = loadSum.load (std::memory_order_relaxed);
        Reading r;
        if (count > lastCount)
        {
            r.average = (sum - lastSum) / (double) (count - lastCount);
            r.valid = true;
        }
        r.peak = peak.exchange (0.0, std::memory_order_relaxed);
        lastCount = count;
        lastSum = sum;
        return r;
    }

    int overloads() const noexcept { return overloadCount.load (std::memory_order_relaxed); }
    void resetOverloads() noexcept { overloadCount.store (0, std::memory_order_relaxed); }

    void audioDeviceAboutToStart (juce::AudioIODevice* device) override
    {
        sampleRate = device->getCurrentSampleRate();
        ticksPerSecond = (double) juce::Time::getHighResolutionTicksPerSecond();
        overloadCount.store (0);
        target.audioDeviceAboutToStart (device);
    }

    void audioDeviceStopped() override { target.audioDeviceStopped(); }
    void audioDeviceError (const juce::String& message) override { target.audioDeviceError (message); }

    void audioDeviceIOCallbackWithContext (const float* const* inputChannelData, int numInputChannels,
                                           float* const* outputChannelData, int numOutputChannels,
                                           int numSamples,
                                           const juce::AudioIODeviceCallbackContext& context) override
    {
        const auto start = juce::Time::getHighResolutionTicks();
        target.audioDeviceIOCallbackWithContext (inputChannelData, numInputChannels,
                                                 outputChannelData, numOutputChannels, numSamples, context);
        if (sampleRate <= 0.0 || numSamples <= 0)
            return;

        const auto seconds = (double) (juce::Time::getHighResolutionTicks() - start) / ticksPerSecond;
        const auto load = seconds / ((double) numSamples / sampleRate);

        loadSum.store (loadSum.load (std::memory_order_relaxed) + load, std::memory_order_relaxed);
        loadCount.store (loadCount.load (std::memory_order_relaxed) + 1, std::memory_order_relaxed);
        if (load > peak.load (std::memory_order_relaxed))
            peak.store (load, std::memory_order_relaxed);
        if (load > 1.0)
            overloadCount.fetch_add (1, std::memory_order_relaxed);
    }

private:
    juce::AudioIODeviceCallback& target;
    double sampleRate = 0.0, ticksPerSecond = 1.0;

    // Single writer (audio thread): monotonic sums, the reader computes differences.
    std::atomic<double> loadSum { 0.0 }, peak { 0.0 };
    std::atomic<juce::int64> loadCount { 0 };
    std::atomic<int> overloadCount { 0 };

    // Reader side only.
    double lastSum = 0.0;
    juce::int64 lastCount = 0;
};
