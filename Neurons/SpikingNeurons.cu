#include "SpikingNeurons.h"
#include <stdlib.h>
#include "../Helpers/CUDAErrorCheckHelpers.h"


// SpikingNeurons Constructor
SpikingNeurons::SpikingNeurons() {

	after_spike_reset_membrane_potentials_c = NULL;
	thresholds_for_action_potential_spikes = NULL;
	param_d = NULL;

	d_last_spike_time_of_each_neuron = NULL;
	d_membrane_potentials_v = NULL;
	d_thresholds_for_action_potential_spikes = NULL;
	d_resting_potentials = NULL;

	d_states_u = NULL;
	d_param_d = NULL;

	recent_postsynaptic_activities_D = NULL;
	d_recent_postsynaptic_activities_D = NULL;

	reversal_potentials_Vhat = NULL;
	d_reversal_potentials_Vhat = NULL;
}


// SpikingNeurons Destructor
SpikingNeurons::~SpikingNeurons() {
	free(recent_postsynaptic_activities_D);
	CudaSafeCall(cudaFree(d_recent_postsynaptic_activities_D));
}


int SpikingNeurons::AddGroup(neuron_parameters_struct * group_params, int group_shape[2]){
	
	int new_group_id = Neurons::AddGroup(group_params, group_shape);

	spiking_neuron_parameters_struct * spiking_group_params = (spiking_neuron_parameters_struct*)group_params;

	after_spike_reset_membrane_potentials_c = (float*)realloc(after_spike_reset_membrane_potentials_c, (total_number_of_neurons*sizeof(float)));
	thresholds_for_action_potential_spikes = (float*)realloc(thresholds_for_action_potential_spikes, (total_number_of_neurons*sizeof(float)));
	param_d = (float*)realloc(param_d, (total_number_of_neurons*sizeof(float)));
	recent_postsynaptic_activities_D = (float*)realloc(recent_postsynaptic_activities_D, (total_number_of_neurons*sizeof(float)));
	reversal_potentials_Vhat = (float*)realloc(reversal_potentials_Vhat, total_number_of_neurons*sizeof(float));

	for (int i = total_number_of_neurons - number_of_neurons_in_new_group; i < total_number_of_neurons; i++) {
		after_spike_reset_membrane_potentials_c[i] = spiking_group_params->resting_potential_v0;
		thresholds_for_action_potential_spikes[i] = spiking_group_params->threshold_for_action_potential_spike;

		//Izhikevich extra
		param_d[i] = spiking_group_params->paramd;

		//LIF extra
		recent_postsynaptic_activities_D[i] = 0.0f;
		reversal_potentials_Vhat[i] = spiking_group_params->reversal_potential_Vhat; //Currently needs to be at SpikingNeuron level so that poisson spiking neurons can have reversal potential
	}

	return new_group_id;
}


void SpikingNeurons::allocate_device_pointers() {

	Neurons::allocate_device_pointers();

	CudaSafeCall(cudaMalloc((void **)&d_last_spike_time_of_each_neuron, sizeof(float)*total_number_of_neurons));

	CudaSafeCall(cudaMalloc((void **)&d_membrane_potentials_v, sizeof(float)*total_number_of_neurons));
	CudaSafeCall(cudaMalloc((void **)&d_thresholds_for_action_potential_spikes, sizeof(float)*total_number_of_neurons));
	CudaSafeCall(cudaMalloc((void **)&d_resting_potentials, sizeof(float)*total_number_of_neurons));
 	
 	//Izhikevich extra
 	CudaSafeCall(cudaMalloc((void **)&d_states_u, sizeof(float)*total_number_of_neurons));
 	CudaSafeCall(cudaMalloc((void **)&d_param_d, sizeof(float)*total_number_of_neurons));

 	//LIF extra
 	 CudaSafeCall(cudaMalloc((void **)&d_recent_postsynaptic_activities_D, sizeof(float)*total_number_of_neurons));
 	  CudaSafeCall(cudaMalloc((void **)&d_reversal_potentials_Vhat, sizeof(float)*total_number_of_neurons));

}

void SpikingNeurons::reset_neurons() {

	Neurons::reset_neurons();

	CudaSafeCall(cudaMemset(d_last_spike_time_of_each_neuron, -1000.0f, total_number_of_neurons*sizeof(float)));

	CudaSafeCall(cudaMemcpy(d_membrane_potentials_v, after_spike_reset_membrane_potentials_c, sizeof(float)*total_number_of_neurons, cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemcpy(d_thresholds_for_action_potential_spikes, thresholds_for_action_potential_spikes, sizeof(float)*total_number_of_neurons, cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemcpy(d_resting_potentials, after_spike_reset_membrane_potentials_c, sizeof(float)*total_number_of_neurons, cudaMemcpyHostToDevice));

	//Izhikevich extra
	CudaSafeCall(cudaMemset(d_states_u, 0.0f, sizeof(float)*total_number_of_neurons));
	CudaSafeCall(cudaMemcpy(d_param_d, param_d, sizeof(float)*total_number_of_neurons, cudaMemcpyHostToDevice));

	//LIF extra
	CudaSafeCall(cudaMemcpy(d_recent_postsynaptic_activities_D, recent_postsynaptic_activities_D, sizeof(float)*total_number_of_neurons, cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemcpy(d_reversal_potentials_Vhat, reversal_potentials_Vhat, sizeof(float)*total_number_of_neurons, cudaMemcpyHostToDevice));

}


void SpikingNeurons::update_membrane_potentials(float timestep) {
	
}

void SpikingNeurons::update_postsynaptic_activities(float timestep, float current_time_in_seconds) {
	
}


__global__ void check_for_neuron_spikes_kernal(float *d_membrane_potentials_v,
								float *d_thresholds_for_action_potential_spikes,
								float *d_states_u,
								float *d_resting_potentials,
								float *d_param_d,
								float* d_last_spike_time_of_each_neuron,
								float currtime,
								size_t total_number_of_neurons);


void SpikingNeurons::check_for_neuron_spikes(float currtime) {

	check_for_neuron_spikes_kernal<<<number_of_neuron_blocks_per_grid, threads_per_block>>>(d_membrane_potentials_v,
																	d_thresholds_for_action_potential_spikes,
																	d_states_u,
																	d_resting_potentials,
																	d_param_d,
																	d_last_spike_time_of_each_neuron,
																	currtime,
																	total_number_of_neurons);

	CudaCheckError();
}


// Spiking Neurons
__global__ void check_for_neuron_spikes_kernal(float *d_membrane_potentials_v,
								float *d_thresholds_for_action_potential_spikes,
								float *d_states_u,
								float *d_resting_potentials,
								float *d_param_d,
								float* d_last_spike_time_of_each_neuron,
								float currtime,
								size_t total_number_of_neurons) {

	// Get thread IDs
	int idx = threadIdx.x + blockIdx.x * blockDim.x;
	while (idx < total_number_of_neurons) {

		if (d_membrane_potentials_v[idx] >= d_thresholds_for_action_potential_spikes[idx]){

			// Set current time as last spike time of neuron
			d_last_spike_time_of_each_neuron[idx] = currtime;

			// Reset membrane potential
			d_membrane_potentials_v[idx] = d_resting_potentials[idx];

			//Izhikevich extra reset
			d_states_u[idx] += d_param_d[idx];
			
		}

		idx += blockDim.x * gridDim.x;
	}
	__syncthreads();

}
