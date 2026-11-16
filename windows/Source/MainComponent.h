#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_audio_utils/juce_audio_utils.h>

#include "MeteredCallback.h"
#include "UpdateChecker.h"

/** Jauge horizontale : vert, orange au-delà de 70 %, rouge au-delà de 90 %. */
class LoadGauge final : public juce::Component, public juce::SettableTooltipClient
{
public:
    void setValue (double v)
    {
        v = juce::jlimit (0.0, 1.0, v);
        if (! juce::exactlyEqual (v, value)) { value = v; repaint(); }
    }

    void paint (juce::Graphics& g) override
    {
        auto r = getLocalBounds().toFloat();
        g.setColour (juce::Colours::black.withAlpha (0.35f));
        g.fillRoundedRectangle (r, 3.0f);
        g.setColour (value < 0.7 ? juce::Colour (0xff3fb950) : value < 0.9 ? juce::Colour (0xffd29922) : juce::Colour (0xfff85149));
        g.fillRoundedRectangle (r.withWidth (r.getWidth() * (float) value), 3.0f);
        g.setColour (juce::Colours::white.withAlpha (0.25f));
        g.drawRoundedRectangle (r.reduced (0.5f), 3.0f, 1.0f);
    }

private:
    double value = 0.0;
};

/** Fenêtre principale : réglages d'interface audio + un seul plugin VST3 en 2 entrées / 2 sorties. */
class MainComponent final : public juce::Component,
                            private juce::Timer,
                            private juce::ChangeListener,
                            private juce::ComponentListener
{
public:
    explicit MainComponent (juce::ApplicationProperties& properties);
    ~MainComponent() override;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    class PluginScanner;

    // Interface
    void timerCallback() override;
    void changeListenerCallback (juce::ChangeBroadcaster*) override;
    void componentMovedOrResized (juce::Component&, bool wasMoved, bool wasResized) override;
    int layout (bool apply);
    void updateSize();
    void setStatus (const juce::String& text, bool isError);
    void refreshStatus();

    // Plugins
    void startScan();
    void refreshEffects();
    void loadSelectedPlugin();
    void pluginLoaded (const juce::PluginDescription&, int token, std::unique_ptr<juce::AudioPluginInstance>, const juce::String& error);
    void unloadPlugin();
    void savePluginState();

    // Mises à jour
    void checkForUpdates (bool interactive);

    juce::ApplicationProperties& props;
    juce::TooltipWindow tooltipWindow { this };

    juce::AudioDeviceManager deviceManager;
    juce::AudioProcessorPlayer player;
    MeteredCallback meter { player };

    juce::AudioPluginFormatManager formatManager;
    juce::KnownPluginList knownPlugins;
    std::vector<juce::PluginDescription> effects;
    std::unique_ptr<juce::AudioPluginInstance> plugin;
    juce::String currentPluginKey;
    int loadToken = 0;
    bool loading = false;

    std::unique_ptr<juce::AudioDeviceSelectorComponent> selector;
    juce::Label loadTitle, latencyTitle, pluginRowTitle, loadLabel, latencyLabel, statusLabel;
    LoadGauge gauge;
    juce::ComboBox pluginBox;
    juce::TextButton rescanButton, updateButton;
    juce::Component editorHolder;
    std::unique_ptr<juce::AudioProcessorEditor> editor;

    juce::String statusText;
    bool statusIsError = false;
    double shownLoad = 0.0, peakHold = 0.0, peakHoldSince = 0.0;

    std::unique_ptr<PluginScanner> scanner;
    UpdateChecker updateChecker;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MainComponent)
};
