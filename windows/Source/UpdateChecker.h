#pragma once

#include <juce_core/juce_core.h>
#include <juce_events/juce_events.h>
#include <functional>

/** Queries the latest GitHub release (one HTTPS request, no personal data).
    Downloads and installs nothing: the user is sent to the download page. */
class UpdateChecker final : private juce::Thread
{
public:
    static constexpr const char* repo = "FLORIANSV35/SimplePlug";
    static constexpr const char* windowsAssetSuffix = "-windows-x64.zip";

    struct Result
    {
        bool ok = false;
        juce::String tag, pageUrl, downloadUrl; // empty downloadUrl: no Windows build (yet)
    };

    UpdateChecker() : juce::Thread ("UpdateChecker") {}
    ~UpdateChecker() override { stopThread (3000); }

    /** `callback` is called on the message thread. */
    void check (std::function<void (Result)> callback)
    {
        if (isThreadRunning())
            return;
        onResult = std::move (callback);
        startThread();
    }

    static bool isNewer (const juce::String& a, const juce::String& b)
    {
        auto parts = [] (juce::String s)
        {
            juce::Array<int> out;
            for (auto& p : juce::StringArray::fromTokens (s.trimCharactersAtStart ("vV"), ".", {}))
                out.add (p.initialSectionContainingOnly ("0123456789").getIntValue());
            return out;
        };
        const auto x = parts (a), y = parts (b);
        for (int i = 0; i < juce::jmax (x.size(), y.size()); ++i)
        {
            const int l = i < x.size() ? x[i] : 0, r = i < y.size() ? y[i] : 0;
            if (l != r)
                return l > r;
        }
        return false;
    }

private:
    void run() override
    {
        Result result;
        const juce::URL url (juce::String ("https://api.github.com/repos/") + repo + "/releases/latest");
        auto stream = url.createInputStream (
            juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inAddress)
                .withExtraHeaders ("Accept: application/vnd.github+json\r\nUser-Agent: SimplePlug-Updater")
                .withConnectionTimeoutMs (15000));

        if (stream != nullptr)
        {
            const auto json = juce::JSON::parse (stream->readEntireStreamAsString());
            result.tag = json["tag_name"].toString();
            result.pageUrl = json["html_url"].toString();
            result.ok = result.tag.isNotEmpty();

            if (auto* assets = json["assets"].getArray())
                for (auto& asset : *assets)
                    if (asset["name"].toString().endsWithIgnoreCase (windowsAssetSuffix))
                        result.downloadUrl = asset["browser_download_url"].toString();
        }

        auto callback = onResult;
        juce::MessageManager::callAsync ([callback, result] { if (callback) callback (result); });
    }

    std::function<void (Result)> onResult;
};
