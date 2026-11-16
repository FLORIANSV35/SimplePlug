#include <juce_gui_basics/juce_gui_basics.h>

#include "MainComponent.h"

namespace
{
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
