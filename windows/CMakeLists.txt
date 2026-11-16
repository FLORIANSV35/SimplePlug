cmake_minimum_required(VERSION 3.22)

# Statically linked C++ runtime: no need to install the Visual C++ Redistributable.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Version YY.MM.XX comes from the git history (see ../version.sh). Override with -DSIMPLEPLUG_VERSION=26.11.12
# (needed on Windows, where the CI passes it in).
if(NOT DEFINED SIMPLEPLUG_VERSION)
    set(SIMPLEPLUG_VERSION "0.0.0")
    if(NOT WIN32)
        execute_process(COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/../version.sh" --plain
                        OUTPUT_VARIABLE _version RESULT_VARIABLE _rc
                        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
        if(_rc EQUAL 0 AND _version MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
            set(SIMPLEPLUG_VERSION "${_version}")
        endif()
    endif()
endif()
# CMake/JUCE need a numeric version without leading zeros (26.11.02 -> 26.11.2);
# the displayed string keeps the zero-padded form.
string(REGEX REPLACE "\\.0+([0-9])" ".\\1" SIMPLEPLUG_VERSION_NUMERIC "${SIMPLEPLUG_VERSION}")

project(SimplePlug VERSION ${SIMPLEPLUG_VERSION_NUMERIC} LANGUAGES C CXX)
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
    ICON_BIG "${CMAKE_CURRENT_SOURCE_DIR}/../assets/icon-windows.png"
    VERSION ${PROJECT_VERSION})

target_sources(SimplePlug PRIVATE
    Source/Main.cpp
    Source/MainComponent.cpp
    Source/MainComponent.h
    Source/MeteredCallback.h
    Source/UpdateChecker.h)

target_compile_definitions(SimplePlug PRIVATE
    JUCE_APPLICATION_NAME_STRING="SimplePlug"
    JUCE_APPLICATION_VERSION_STRING="${SIMPLEPLUG_VERSION}"
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_PLUGINHOST_VST3=1
    JUCE_PLUGINHOST_VST=0
    JUCE_PLUGINHOST_AU=0
    JUCE_PLUGINHOST_LADSPA=0
    JUCE_PLUGINHOST_LV2=0
    JUCE_ASIO=1          # ASIO interfaces (headers bundled with JUCE); ignored outside Windows
    JUCE_WASAPI=1
    JUCE_DIRECTSOUND=1)

target_compile_options(SimplePlug PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/utf-8>)  # sources are UTF-8

target_link_libraries(SimplePlug
    PRIVATE
        juce::juce_audio_utils
        juce::juce_audio_devices
        juce::juce_audio_processors
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags)
