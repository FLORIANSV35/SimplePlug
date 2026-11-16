#include <juce_gui_basics/juce_gui_basics.h>

#include "MainComponent.h"

namespace
{
    // Traduction française du sélecteur d'interface audio de JUCE.
    const char* frenchStrings = R"LOC(
language: French
"Audio device type:" = "Type d'interface :"
"Output:" = "Sortie :"
"Input:" = "Entrée :"
"Sample rate:" = "Fréquence :"
"Audio buffer size:" = "Taille du buffer :"
"Active output channels:" = "Canaux de sortie :"
"Active input channels:" = "Canaux d'entrée :"
"Device:" = "Interface :"
"Control Panel" = "Panneau de contrôle"
"Opens the device's own control panel" = "Ouvre le panneau de contrôle du pilote"
"Test" = "Test"
"Plays a test tone" = "Joue un son de test"
"Reset Device" = "Réinitialiser"
"Resets the audio interface - sometimes needed after changing a device's properties in its custom control panel" = "Réinitialise l'interface audio (parfois nécessaire après un changement dans son panneau de contrôle)"
"Show advanced settings..." = "Réglages avancés..."
"none" = "aucun"
"(no audio input channels found)" = "(aucun canal d'entrée)"
"(no audio output channels found)" = "(aucun canal de sortie)"
"Error when trying to open audio device!" = "Impossible d'ouvrir l'interface audio !"
)LOC";

    class MainWindow final : public juce::DocumentWindow
    {
    public:
        MainWindow (const juce::String& name, juce::ApplicationProperties& props)
            : juce::DocumentWindow (name,
                                    juce::Desktop::getInstance().getDefaultLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId),
                                    juce::DocumentWindow::allButtons ^ juce::DocumentWindow::maximiseButton)
        {
            setUsingNativeTitleBar (true);
            setContentOwned (new MainComponent (props), true);
            setResizable (false, false);
            centreWithSize (getWidth(), getHeight());
            setVisible (true);
        }

        void closeButtonPressed() override { juce::JUCEApplication::getInstance()->systemRequestedQuit(); }
    };
}

class SimplePlugApplication final : public juce::JUCEApplication
{
public:
    const juce::String getApplicationName() override    { return JUCE_APPLICATION_NAME_STRING; }
    const juce::String getApplicationVersion() override { return JUCE_APPLICATION_VERSION_STRING; }
    bool moreThanOneInstanceAllowed() override          { return false; }

    void initialise (const juce::String&) override
    {
        juce::PropertiesFile::Options options;
        options.applicationName = getApplicationName();
        options.filenameSuffix = ".settings";
        options.osxLibrarySubFolder = "Application Support";
        options.folderName = getApplicationName();
        properties.setStorageParameters (options);

        juce::LocalisedStrings::setCurrentMappings (new juce::LocalisedStrings (juce::String::fromUTF8 (frenchStrings), false));

        window = std::make_unique<MainWindow> (getApplicationName(), properties);
    }

    void shutdown() override
    {
        window.reset();
        properties.closeFiles();
    }

    void systemRequestedQuit() override { quit(); }

    void anotherInstanceStarted (const juce::String&) override
    {
        if (window != nullptr)
            window->toFront (true);
    }

private:
    juce::ApplicationProperties properties;
    std::unique_ptr<MainWindow> window;
};

START_JUCE_APPLICATION (SimplePlugApplication)
