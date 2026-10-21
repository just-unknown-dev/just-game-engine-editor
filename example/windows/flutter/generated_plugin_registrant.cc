//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <just_audio_engine/just_audio_engine_plugin.h>
#include <just_gamepads/just_gamepads_plugin_c_api.h>
#include <just_inputs/just_inputs_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  JustAudioEnginePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("JustAudioEnginePlugin"));
  JustGamepadsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("JustGamepadsPluginCApi"));
  JustInputsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("JustInputsPluginCApi"));
}
