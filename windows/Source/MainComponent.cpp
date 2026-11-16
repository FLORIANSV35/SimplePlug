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

    /** Force le bus principal en stéréo (et désactive les bus annexes, ex. sidechain). */
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
/** Analyse les dossiers VST3 dans un thread. Un fichier « dead man's pedal » mémorise le plugin en cours
    d'analyse : s'il plante l'application, il sera ignoré au prochain essai. */
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

    // Interface audio : exactement 2 entrées / 2 sorties.
    const auto savedDevice = settings.getXmlValue ("audioDevice");
    const auto error = deviceManager.initialise (2, 2, savedDevice.get(), true);
    deviceManager.addChangeListener (this);
    deviceManager.addAudioCallback (&meter);

    selector = std::make_unique<juce::AudioDeviceSelectorComponent> (deviceManager, 2, 2, 2, 2,
                                                                     false, false, true, false);
    selector->setSize (minWidth - 2 * margin, 220);
    selector->addComponentListener (this);
    addAndMakeVisible (*selector);

    styleTitle (loadTitle, T8 ("Charge buffer"));
    styleTitle (latencyTitle, T8 ("Latence"));
    styleTitle (pluginRowTitle, T8 ("Plugin VST3"));
    for (auto* l : { &loadTitle, &latencyTitle, &pluginRowTitle })
        addAndMakeVisible (*l);

    addAndMakeVisible (gauge);
    loadLabel.setFont (juce::Font (juce::FontOptions (juce::Font::getDefaultMonospacedFontName(), 13.0f, juce::Font::plain)));
    loadLabel.setTooltip (T8 ("Temps de calcul / durée du buffer. Au-delà de 100 %, l'audio craque (« dépassement »)."));
    gauge.setTooltip (loadLabel.getTooltip());
    latencyLabel.setColour (juce::Label::textColourId, juce::Colours::grey);
    loadLabel.setColour (juce::Label::textColourId, juce::Colours::grey);
    for (auto* l : { &loadLabel, &latencyLabel, &statusLabel })
        addAndMakeVisible (*l);

    addAndMakeVisible (pluginBox);
    pluginBox.setTextWhenNothingSelected (T8 ("Aucun (signal direct)"));
    pluginBox.onChange = [this]
    {
        const int index = pluginBox.getSelectedId() - 2;
        props.getUserSettings()->setValue ("pluginKey", index >= 0 ? effects[(size_t) index].createIdentifierString() : juce::String());
        loadSelectedPlugin();
    };

    rescanButton.setButtonText (T8 ("Rescanner"));
    rescanButton.setTooltip (T8 ("Rechercher à nouveau les plugins VST3 installés"));
    rescanButton.onClick = [this] { startScan(); };
    addAndMakeVisible (rescanButton);

    updateButton.setButtonText (T8 ("Mises à jour"));
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
        setStatus (T8 ("Aucune interface audio ouverte."), true);
        return;
    }

    const double rate = device->getCurrentSampleRate();
    const double latencyMs = (device->getInputLatencyInSamples() + device->getOutputLatencyInSamples()) / rate * 1000.0;
    latencyLabel.setText (T8 ("\xe2\x89\x88 ") + juce::String (latencyMs, 1) + T8 (" ms (aller-retour)"), juce::dontSendNotification);

    if (! loading)
        setStatus (T8 ("En marche \xe2\x80\x94 ") + juce::String (juce::roundToInt (rate)) + " Hz, "
                       + juce::String (device->getCurrentBufferSizeSamples()) + T8 (" \xc3\xa9" "chantillons \xe2\x80\x94 ")
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

    // Montée immédiate, descente lissée ; le pic est maintenu 1,5 s.
    shownLoad = juce::jmax (r.average, shownLoad * 0.85);
    const double now = juce::Time::getMillisecondCounterHiRes();
    if (r.peak >= peakHold || now - peakHoldSince > 1500.0)
    {
        peakHold = r.peak;
        peakHoldSince = now;
    }

    gauge.setValue (shownLoad);

    auto text = juce::String::formatted ("%3.0f %%  (pic %3.0f %%)", shownLoad * 100.0, peakHold * 100.0);
    const int overloads = meter.overloads();
    if (overloads > 0)
        text += "  (!) " + juce::String (overloads) + T8 (" d\xc3\xa9passement") + (overloads > 1 ? "s" : "");
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
    setStatus (T8 ("Analyse des plugins VST3\xe2\x80\xa6"), false);

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
                    safe->setStatus (T8 ("Analyse : ") + juce::File::createFileWithoutCheckingPath (file).getFileName(), false);
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
    pluginBox.addItem (T8 ("Aucun (signal direct)"), 1);
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
    setStatus (T8 ("Chargement de \xc2\xab ") + desc.name + T8 (" \xc2\xbb\xe2\x80\xa6"), false);

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
        return; // une sélection plus récente est en cours

    loading = false;
    pluginBox.setEnabled (true);

    if (instance == nullptr)
    {
        setStatus (T8 ("Impossible de charger le plugin : ") + error, true);
        return;
    }
    if (! configureStereo (*instance))
    {
        setStatus (T8 ("Ce plugin n'accepte pas 2 entr\xc3\xa9" "es / 2 sorties."), true);
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

    // Le premier buffer après le chargement est toujours plus long : on ne le compte pas comme une coupure.
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
            info (T8 ("Impossible de v\xc3\xa9rifier les mises \xc3\xa0 jour"), T8 ("GitHub n'a pas r\xc3\xa9pondu."));
            return;
        }
        safe->props.getUserSettings()->setValue ("lastUpdateCheck", (double) juce::Time::currentTimeMillis());

        if (! UpdateChecker::isNewer (r.tag, version))
        {
            info (T8 ("Vous \xc3\xaates \xc3\xa0 jour"), "SimplePlug " + version + T8 (" est la derni\xc3\xa8re version."));
            return;
        }
        if (r.downloadUrl.isEmpty())
        {
            info (T8 ("Mise \xc3\xa0 jour"), T8 ("La version ") + r.tag + T8 (" existe, mais sans build Windows pour le moment."));
            return;
        }

        const auto url = r.downloadUrl;
        juce::AlertWindow::showAsync (
            juce::MessageBoxOptions()
                .withIconType (juce::MessageBoxIconType::InfoIcon)
                .withTitle ("SimplePlug " + r.tag.trimCharactersAtStart ("vV") + T8 (" est disponible"))
                .withMessage (T8 ("Vous utilisez la version ") + version + T8 (".\n\nT\xc3\xa9l\xc3\xa9" "charger la mise \xc3\xa0 jour ?"))
                .withButton (T8 ("T\xc3\xa9l\xc3\xa9" "charger"), 1)
                .withButton (T8 ("Plus tard"), 0),
            [url] (int result)
            {
                if (result == 1)
                    juce::URL (url).launchInDefaultBrowser();
            });
    });
}
