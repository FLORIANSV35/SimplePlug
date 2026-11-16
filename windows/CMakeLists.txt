cmake_minimum_required(VERSION 3.22)

# Runtime C++ lié statiquement : pas besoin d'installer les « Visual C++ Redistributable ».
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

project(SimplePlug VERSION 1.0.2 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)
FetchContent_Declare(JUCE
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG        9.0.5
    GIT_SHALLOW    ON)
FetchContent_MakeAvailable(JUCE)

juce_add_gui_app(SimplePlug
    PRODUCT_NAME "SimplePlug"
    COMPANY_NAME "SimplePlug"
    VERSION ${PROJECT_VERSION})

target_sources(SimplePlug PRIVATE
    Source/Main.cpp
    Source/MainComponent.cpp
    Source/MainComponent.h
    Source/MeteredCallback.h
    Source/UpdateChecker.h)

target_compile_definitions(SimplePlug PRIVATE
    JUCE_APPLICATION_NAME_STRING="SimplePlug"
    JUCE_APPLICATION_VERSION_STRING="${PROJECT_VERSION}"
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_PLUGINHOST_VST3=1
    JUCE_PLUGINHOST_VST=0
    JUCE_PLUGINHOST_AU=0
    JUCE_PLUGINHOST_LADSPA=0
    JUCE_PLUGINHOST_LV2=0
    JUCE_ASIO=1          # interfaces ASIO (en-têtes fournis avec JUCE) ; ignoré hors Windows
    JUCE_WASAPI=1
    JUCE_DIRECTSOUND=1)

target_compile_options(SimplePlug PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/utf-8>)  # sources en UTF-8 (accents)

target_link_libraries(SimplePlug
    PRIVATE
        juce::juce_audio_utils
        juce::juce_audio_devices
        juce::juce_audio_processors
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags)
