#include "MainComponent.h"

namespace
{
    juce::String T8 (const char* utf8) { return juce::String::fromUTF8 (utf8); }

    constexpr int margin = 16, rowH = 26, labelW = 130, minWidth = 560;

    juce::String titleOf (const juce::PluginDescription& d)
    {
        if (d.manufacturerName.isEmpty() || d.name.containsIgnoreCase (d.manufacturerName))
            return d.name;
        return d.manufacturerName + ": " + d.name;
    }

    /** Forces the main bus to stereo (and disables auxiliary buses, e.g. sidechain). */
    bool configureStereo (juce::AudioPluginInstance& p)
    {
        auto layout = p.getBusesLayout();
        for (int i = 0; i < layout.inputBuses.size(); ++i)
            layout.inputBuses.getReference (i) = i == 0 ? juce::AudioChannelSet::stereo() : juce::AudioChannelSet::disabled();
        for (int i = 0; i < layout.outputBuses.size(); ++i)
            layout.outputBuses.getReference (i) = i == 0 ? juce::AudioChannelSet::stereo() : juce::AudioChannelSet::disabled();
        return p.setBusesLayout (layout);
    }

    void styleTitle (juce::Label& l, const juce::String& text)
    {
        l.setText (text, juce::dontSendNotification);
        l.setJustificationType (juce::Justification::centredRight);
    }
}

//==============================================================================
/** Scans the VST3 folders on a thread. A "dead man's pedal" file remembers the plugin being scanned:
    if it crashes the application, it is skipped on the next attempt. */
class MainComponent::PluginScanner final : public juce::Thread
{
public:
    PluginScanner (juce::KnownPluginList& knownList, juce::AudioPluginFormat& pluginFormat, juce::File deadMansFile,
                   std::function<void (juce::String)> progress, std::function<void()> done)
        : juce::Thread ("PluginScanner"), list (knownList), format (pluginFormat), deadMans (std::move (deadMansFile)),
          onProgress (std::move (progress)), onDone (std::move (done))
    {
        startThread();
    }

    ~PluginScanner() override { stopThread (5000); }

    void run() override
    {
        juce::PluginDirectoryScanner dirScanner (list, format, format.getDefaultLocationsToSearch(), true, deadMans);
        juce::String name;

        while (! threadShouldExit())
        {
            onProgress (dirScanner.getNextPluginFileThatWillBeScanned());
            if (! dirScanner.scanNextFile (true, name))
                break;
        }
        onDone();
    }

private:
    juce::KnownPluginList& list;
    juce::AudioPluginFormat& format;
    juce::File deadMans;
    std::function<void (juce::String)> onProgress;
    std::function<void()> onDone;
};

//==============================================================================
MainComponent::MainComponent (juce::ApplicationProperties& properties) : props (properties)
{
    auto& settings = *props.getUserSettings();

    formatManager.addFormat (std::make_unique<juce::VST3PluginFormat>());
    if (auto xml = settings.getXmlValue ("knownPlugins"))
        knownPlugins.recreateFromXml (*xml);

    // Audio interface: exactly 2 inputs / 2 outputs.
    const auto savedDevice = settings.getXmlValue ("audioDevice");
    const auto error = deviceManager.initialise (2, 2, savedDevice.get(), true);
    deviceManager.addChangeListener (this);
    deviceManager.addAudioCallback (&meter);

    selector = std::make_unique<juce::AudioDeviceSelectorComponent> (deviceManager, 2, 2, 2, 2,
                                                                     false, false, true, false);
    selector->setSize (minWidth - 2 * margin, 220);
    selector->addComponentListener (this);
    addAndMakeVisible (*selector);

    styleTitle (loadTitle, "Buffer load");
    styleTitle (latencyTitle, "Latency");
    styleTitle (pluginRowTitle, "VST3 plugin");
    for (auto* l : { &loadTitle, &latencyTitle, &pluginRowTitle })
        addAndMakeVisible (*l);

    addAndMakeVisible (gauge);
    loadLabel.setFont (juce::Font (juce::FontOptions (juce::Font::getDefaultMonospacedFontName(), 13.0f, juce::Font::plain)));
    loadLabel.setTooltip (T8 ("Compute time / buffer duration. Above 100 %, the audio crackles (an \xe2\x80\x9coverrun\xe2\x80\x9d)."));
    gauge.setTooltip (loadLabel.getTooltip());
    latencyLabel.setColour (juce::Label::textColourId, juce::Colours::grey);
    loadLabel.setColour (juce::Label::textColourId, juce::Colours::grey);
    for (auto* l : { &loadLabel, &latencyLabel, &statusLabel })
        addAndMakeVisible (*l);

    addAndMakeVisible (pluginBox);
    pluginBox.setTextWhenNothingSelected ("None (pass-through)");
    pluginBox.onChange = [this]
    {
        const int index = pluginBox.getSelectedId() - 2;
        props.getUserSettings()->setValue ("pluginKey", index >= 0 ? effects[(size_t) index].createIdentifierString() : juce::String());
        loadSelectedPlugin();
    };

    rescanButton.setButtonText ("Rescan");
    rescanButton.setTooltip ("Scan again for installed VST3 plugins");
    rescanButton.onClick = [this] { startScan(); };
    addAndMakeVisible (rescanButton);

    updateButton.setButtonText ("Updates");
    updateButton.onClick = [this] { checkForUpdates (true); };
    addAndMakeVisible (updateButton);

    addAndMakeVisible (editorHolder);

    refreshEffects();
    if (error.isNotEmpty())
        setStatus (T8 ("Interface audio : ") + error, true);
    else
        refreshStatus();

    updateSize();
    startTimer (100);

    if (knownPlugins.getNumTypes() == 0)
        startScan();
    else
        loadSelectedPlugin();

    const double last = settings.getDoubleValue ("lastUpdateCheck", 0.0);
    if (juce::Time::currentTimeMillis() - (juce::int64) last > 24 * 3600 * 1000)
        checkForUpdates (false);
}

MainComponent::~MainComponent()
{
    stopTimer();
    scanner.reset();
    deviceManager.removeChangeListener (this);
    deviceManager.removeAudioCallback (&meter);
    selector->removeComponentListener (this);
    savePluginState();
    unloadPlugin();
    props.saveIfNeeded();
}

//==============================================================================
void MainComponent::paint (juce::Graphics& g)
{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));
}

void MainComponent::resized() { layout (true); }

int MainComponent::layout (bool apply)
{
    const int w = getWidth();
    int y = margin;
    auto place = [apply] (juce::Component& c, juce::Rectangle<int> r) { if (apply) c.setBounds (r); };

    place (*selector, { margin, y, w - 2 * margin, selector->getHeight() });
    y += selector->getHeight() + 10;

    place (loadTitle, { margin, y, labelW, rowH });
    place (gauge, { margin + labelW + 10, y + (rowH - 14) / 2, 170, 14 });
    place (loadLabel, { margin + labelW + 190, y, juce::jmax (0, w - (margin + labelW + 190) - margin), rowH });
    y += rowH;

    place (latencyTitle, { margin, y, labelW, rowH });
    place (latencyLabel, { margin + labelW + 10, y, juce::jmax (0, w - (margin + labelW + 10) - margin), rowH });
    y += rowH + 6;

    place (pluginRowTitle, { margin, y, labelW, rowH });
    place (pluginBox, { margin + labelW + 10, y, juce::jmax (0, w - 2 * margin - labelW - 10 - 98), rowH });
    place (rescanButton, { w - margin - 90, y, 90, rowH });
    y += rowH + 10;

    place (statusLabel, { margin, y, juce::jmax (0, w - 2 * margin - 130), rowH });
    place (updateButton, { w - margin - 120, y, 120, rowH });
    y += rowH + 10;

    if (editor != nullptr)
    {
        place (editorHolder, { (w - editorHolder.getWidth()) / 2, y, editorHolder.getWidth(), editorHolder.getHeight() });
        y += editorHolder.getHeight() + margin;
    }
    else
    {
        place (editorHolder, {});
        y += margin - 10;
    }
    return y;
}

void MainComponent::updateSize()
{
    const int editorWidth = editor != nullptr ? editorHolder.getWidth() + 2 * margin : 0;
    const int newWidth = juce::jmax (minWidth, editorWidth);
    if (newWidth != getWidth())
        setSize (newWidth, getHeight());
    setSize (newWidth, layout (false));
    layout (true);
}

void MainComponent::componentMovedOrResized (juce::Component& c, bool, bool wasResized)
{
    if (! wasResized)
        return;
    if (&c == editor.get())
    {
        editorHolder.setSize (editor->getWidth(), editor->getHeight());
        updateSize();
    }
    else if (&c == selector.get())
    {
        updateSize();
    }
}

void MainComponent::setStatus (const juce::String& text, bool isError)
{
    statusText = text;
    statusIsError = isError;
    statusLabel.setText ((isError ? T8 ("(!) ") : T8 ("\xe2\x97\x8f ")) + text, juce::dontSendNotification);
    statusLabel.setTooltip (text);
    statusLabel.setColour (juce::Label::textColourId, isError ? juce::Colour (0xfff85149) : juce::Colours::grey);
}

void MainComponent::refreshStatus()
{
    auto* device = deviceManager.getCurrentAudioDevice();
    if (device == nullptr)
    {
        latencyLabel.setText ({}, juce::dontSendNotification);
        setStatus ("No audio interface open.", true);
        return;
    }

    const double rate = device->getCurrentSampleRate();
    const double latencyMs = (device->getInputLatencyInSamples() + device->getOutputLatencyInSamples()) / rate * 1000.0;
    latencyLabel.setText (T8 ("\xe2\x89\x88 ") + juce::String (latencyMs, 1) + " ms (round trip)", juce::dontSendNotification);

    if (! loading)
        setStatus (T8 ("Running \xe2\x80\x94 ") + juce::String (juce::roundToInt (rate)) + " Hz, "
                       + juce::String (device->getCurrentBufferSizeSamples()) + T8 (" samples \xe2\x80\x94 ")
                       + device->getName(),
                   false);
}

void MainComponent::timerCallback()
{
    if (deviceManager.getCurrentAudioDevice() == nullptr)
    {
        gauge.setValue (0.0);
        loadLabel.setText ({}, juce::dontSendNotification);
        shownLoad = 0.0;
        return;
    }

    const auto r = meter.read();
    if (! r.valid)
        return;

    // Instant rise, smoothed fall; the peak is held for 1.5 s.
    shownLoad = juce::jmax (r.average, shownLoad * 0.85);
    const double now = juce::Time::getMillisecondCounterHiRes();
    if (r.peak >= peakHold || now - peakHoldSince > 1500.0)
    {
        peakHold = r.peak;
        peakHoldSince = now;
    }

    gauge.setValue (shownLoad);

    auto text = juce::String::formatted ("%3.0f %%  (peak %3.0f %%)", shownLoad * 100.0, peakHold * 100.0);
    const int overloads = meter.overloads();
    if (overloads > 0)
        text += "  (!) " + juce::String (overloads) + " overrun" + (overloads > 1 ? "s" : "");
    loadLabel.setText (text, juce::dontSendNotification);
    loadLabel.setColour (juce::Label::textColourId, overloads > 0 ? juce::Colour (0xfff85149) : juce::Colours::grey);
}

void MainComponent::changeListenerCallback (juce::ChangeBroadcaster*)
{
    if (auto xml = deviceManager.createStateXml())
        props.getUserSettings()->setValue ("audioDevice", xml.get());
    refreshStatus();
}

//==============================================================================
void MainComponent::startScan()
{
    if (scanner != nullptr)
        return;

    rescanButton.setEnabled (false);
    setStatus (T8 ("Scanning VST3 plugins\xe2\x80\xa6"), false);

    juce::Component::SafePointer<MainComponent> safe (this);
    auto* format = formatManager.getFormats().getFirst();
    const auto deadMans = props.getUserSettings()->getFile().getSiblingFile ("scan-crash.txt");

    scanner = std::make_unique<PluginScanner> (
        knownPlugins, *format, deadMans,
        [safe] (juce::String file)
        {
            juce::MessageManager::callAsync ([safe, file]
            {
                if (safe != nullptr)
                    safe->setStatus ("Scanning: " + juce::File::createFileWithoutCheckingPath (file).getFileName(), false);
            });
        },
        [safe]
        {
            juce::MessageManager::callAsync ([safe]
            {
                if (safe == nullptr)
                    return;
                auto& s = *safe;
                if (auto xml = s.knownPlugins.createXml())
                    s.props.getUserSettings()->setValue ("knownPlugins", xml.get());
                s.props.saveIfNeeded();
                s.scanner.reset();
                s.rescanButton.setEnabled (true);
                s.refreshEffects();
                s.refreshStatus();
                if (s.plugin == nullptr && ! s.loading && s.pluginBox.getSelectedId() > 1)
                    s.loadSelectedPlugin();
            });
        });
}

void MainComponent::refreshEffects()
{
    effects.clear();
    for (auto& d : knownPlugins.getTypes())
        if (! d.isInstrument && d.pluginFormatName == "VST3")
            effects.push_back (d);

    std::sort (effects.begin(), effects.end(), [] (const auto& a, const auto& b)
               { return titleOf (a).compareNatural (titleOf (b), false) < 0; });

    pluginBox.clear (juce::dontSendNotification);
    pluginBox.addItem ("None (pass-through)", 1);
    pluginBox.addSeparator();
    for (size_t i = 0; i < effects.size(); ++i)
        pluginBox.addItem (titleOf (effects[i]), (int) i + 2);

    const auto wanted = props.getUserSettings()->getValue ("pluginKey");
    int id = 1;
    for (size_t i = 0; i < effects.size(); ++i)
        if (effects[i].createIdentifierString() == wanted)
            id = (int) i + 2;
    pluginBox.setSelectedId (id, juce::dontSendNotification);
}

void MainComponent::loadSelectedPlugin()
{
    savePluginState();
    unloadPlugin();

    const int index = pluginBox.getSelectedId() - 2;
    if (index < 0 || index >= (int) effects.size())
    {
        loading = false;
        refreshStatus();
        return;
    }

    const auto desc = effects[(size_t) index];
    loading = true;
    pluginBox.setEnabled (false);
    setStatus (T8 ("Loading \xe2\x80\x9c") + desc.name + T8 ("\xe2\x80\x9d\xe2\x80\xa6"), false);

    auto* device = deviceManager.getCurrentAudioDevice();
    const double rate = device != nullptr ? device->getCurrentSampleRate() : 48000.0;
    const int block = device != nullptr ? device->getCurrentBufferSizeSamples() : 512;
    const int token = ++loadToken;

    juce::Component::SafePointer<MainComponent> safe (this);
    formatManager.createPluginInstanceAsync (desc, rate, block,
        [safe, desc, token] (std::unique_ptr<juce::AudioPluginInstance> instance, const juce::String& error)
        {
            if (safe != nullptr)
                safe->pluginLoaded (desc, token, std::move (instance), error);
        });
}

void MainComponent::pluginLoaded (const juce::PluginDescription& desc, int token,
                                  std::unique_ptr<juce::AudioPluginInstance> instance, const juce::String& error)
{
    if (token != loadToken)
        return; // a more recent selection is in progress

    loading = false;
    pluginBox.setEnabled (true);

    if (instance == nullptr)
    {
        setStatus ("Couldn't load the plugin: " + error, true);
        return;
    }
    if (! configureStereo (*instance))
    {
        setStatus ("This plugin doesn't support 2 inputs / 2 outputs.", true);
        return;
    }

    currentPluginKey = desc.createIdentifierString();
    if (auto saved = props.getUserSettings()->getValue ("state." + currentPluginKey); saved.isNotEmpty())
    {
        juce::MemoryBlock state;
        if (state.fromBase64Encoding (saved))
            instance->setStateInformation (state.getData(), (int) state.getSize());
    }

    plugin = std::move (instance);
    player.setProcessor (plugin.get());

    editor.reset (plugin->hasEditor() ? plugin->createEditorAndMakeActive()
                                      : new juce::GenericAudioProcessorEditor (*plugin));
    if (editor != nullptr)
    {
        editorHolder.setSize (editor->getWidth(), editor->getHeight());
        editorHolder.addAndMakeVisible (*editor);
        editor->setTopLeftPosition (0, 0);
        editor->addComponentListener (this);
    }
    updateSize();
    refreshStatus();

    // The first buffer after loading is always longer: don't count it as a dropout.
    juce::Timer::callAfterDelay (1500, [safe = juce::Component::SafePointer<MainComponent> (this)]
                                 { if (safe != nullptr) safe->meter.resetOverloads(); });
}

void MainComponent::unloadPlugin()
{
    if (editor != nullptr)
        editor->removeComponentListener (this);
    editor.reset();
    player.setProcessor (nullptr);
    plugin.reset();
    currentPluginKey = {};
    editorHolder.setSize (0, 0);
    updateSize();
}

void MainComponent::savePluginState()
{
    if (plugin == nullptr || currentPluginKey.isEmpty())
        return;
    juce::MemoryBlock state;
    plugin->getStateInformation (state);
    props.getUserSettings()->setValue ("state." + currentPluginKey, state.toBase64Encoding());
}

//==============================================================================
void MainComponent::checkForUpdates (bool interactive)
{
    juce::Component::SafePointer<MainComponent> safe (this);
    updateChecker.check ([safe, interactive] (UpdateChecker::Result r)
    {
        if (safe == nullptr)
            return;

        const auto version = juce::String (JUCE_APPLICATION_VERSION_STRING);
        auto info = [interactive] (const juce::String& title, const juce::String& text)
        {
            if (interactive)
                juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::InfoIcon, title, text);
        };

        if (! r.ok)
        {
            info ("Couldn't check for updates", "GitHub didn't respond.");
            return;
        }
        safe->props.getUserSettings()->setValue ("lastUpdateCheck", (double) juce::Time::currentTimeMillis());

        if (! UpdateChecker::isNewer (r.tag, version))
        {
            info ("You're up to date", "SimplePlug " + version + " is the latest version.");
            return;
        }
        if (r.downloadUrl.isEmpty())
        {
            info ("Update", "Version " + r.tag.trimCharactersAtStart ("vV") + " exists, but has no Windows build yet.");
            return;
        }

        const auto url = r.downloadUrl;
        juce::AlertWindow::showAsync (
            juce::MessageBoxOptions()
                .withIconType (juce::MessageBoxIconType::InfoIcon)
                .withTitle ("SimplePlug " + r.tag.trimCharactersAtStart ("vV") + " is available")
                .withMessage ("You're using version " + version + ".\n\nDownload the update?")
                .withButton ("Download", 1)
                .withButton ("Later", 0),
            [url] (int result)
            {
                if (result == 1)
                    juce::URL (url).launchInDefaultBrowser();
            });
    });
}
