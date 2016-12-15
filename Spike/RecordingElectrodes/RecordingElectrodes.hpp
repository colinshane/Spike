#ifndef RecordingElectrodes_H
#define RecordingElectrodes_H

#include <string>
using namespace std;

#include "Spike/Base.hpp"

#include "Spike/Backend/Macros.hpp"
#include "Spike/Backend/Context.hpp"
#include "Spike/Backend/Backend.hpp"
#include "Spike/Backend/Device.hpp"

#include "Spike/Neurons/SpikingNeurons.hpp"
#include "Spike/Synapses/SpikingSynapses.hpp"

class RecordingElectrodes; // forward definition

namespace Backend {
  class RecordingElectrodes : public virtual SpikeBackendBase {
  public:
    ADD_FRONTEND_GETTER(RecordingElectrodes);
  };
}

#include "Spike/Backend/Dummy/RecordingElectrodes/RecordingElectrodes.hpp"
#ifdef SPIKE_WITH_CUDA
#include "Spike/Backend/CUDA/RecordingElectrodes/RecordingElectrodes.hpp"
#endif

class RecordingElectrodes : public virtual SpikeBase {
public:
  RecordingElectrodes(SpikingNeurons * neurons_parameter,
                      SpikingSynapses * synapses_parameter,
                      string full_directory_name_for_simulation_data_files_param,
                      const char * prefix_string_param);

  ADD_BACKEND_GETSET(RecordingElectrodes, SpikeBase);
  void init_backend(Context* ctx = _global_ctx) override;
  void reset_state() override;

  // Variables
  std::string full_directory_name_for_simulation_data_files;
  const char * prefix_string = nullptr;

  // Host Pointers
  SpikingNeurons * neurons = nullptr;
  SpikingSynapses * synapses = nullptr;

private:
  ::Backend::RecordingElectrodes* _backend = nullptr;
};

#endif