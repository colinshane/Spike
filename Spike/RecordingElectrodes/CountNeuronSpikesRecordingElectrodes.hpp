#ifndef CountNeuronSpikesRecordingElectrodes_H
#define CountNeuronSpikesRecordingElectrodes_H


#include "../RecordingElectrodes/RecordingElectrodes.hpp"

class CountNeuronSpikesRecordingElectrodes; // forward definition

namespace Backend {
  class CountNeuronSpikesRecordingElectrodes : public virtual RecordingElectrodes {
  public:
    ADD_FRONTEND_GETTER(CountNeuronSpikesRecordingElectrodes);

    virtual void add_spikes_to_per_neuron_spike_count
    (float current_time_in_seconds) = 0;
  };
}

#include "Spike/Backend/Dummy/RecordingElectrodes/CountNeuronSpikesRecordingElectrodes.hpp"
#ifdef SPIKE_WITH_CUDA
#include "Spike/Backend/CUDA/RecordingElectrodes/CountNeuronSpikesRecordingElectrodes.hpp"
#endif


class CountNeuronSpikesRecordingElectrodes : public RecordingElectrodes {
public:
  ADD_BACKEND_GETSET(CountNeuronSpikesRecordingElectrodes,
                     RecordingElectrodes);
  void init_backend(Context* ctx = _global_ctx) override;
  
  // Constructor/Destructor
  CountNeuronSpikesRecordingElectrodes(SpikingNeurons * neurons_parameter,
                                       SpikingSynapses * synapses_parameter,
                                       string full_directory_name_for_simulation_data_files_param,
                                       const char * prefix_string_param);

  void initialise_count_neuron_spikes_recording_electrodes();

  void add_spikes_to_per_neuron_spike_count(float current_time_in_seconds);

private:
  ::Backend::CountNeuronSpikesRecordingElectrodes* _backend = nullptr;
};

#endif