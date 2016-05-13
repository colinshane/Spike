#include "PoissonSpikingNeurons.h"
#include <stdlib.h>
#include <stdio.h>
#include "../Helpers/CUDAErrorCheckHelpers.h"
#include <algorithm> // For random shuffle
using namespace std;


// PoissonSpikingNeurons Constructor
PoissonSpikingNeurons::PoissonSpikingNeurons() {
	rates = NULL;
	d_rates = NULL;
	d_states = NULL;

	random_state_manager = NULL;
}


// PoissonSpikingNeurons Destructor
PoissonSpikingNeurons::~PoissonSpikingNeurons() {

}


int PoissonSpikingNeurons::AddGroup(neuron_parameters_struct * group_params, int group_shape[2]){

	int new_group_id = SpikingNeurons::AddGroup(group_params, group_shape);

	poisson_spiking_neuron_parameters_struct * poisson_spiking_group_params = (poisson_spiking_neuron_parameters_struct*)group_params;

	rates = (float*)realloc(rates, sizeof(float)*total_number_of_neurons);
	for (int i = total_number_of_neurons - number_of_neurons_in_new_group; i < total_number_of_neurons; i++) {
		rates[i] = poisson_spiking_group_params->rate;
	}


	// printf("POISSON  GROUP ID: %d\n", new_group_id);
	return -1 * new_group_id - 1;

}

void PoissonSpikingNeurons::allocate_device_pointers() {

	SpikingNeurons::allocate_device_pointers();

	CudaSafeCall(cudaMalloc((void **)&d_rates, sizeof(float)*total_number_of_neurons));
	CudaSafeCall(cudaMalloc((void**) &d_states, sizeof(curandState_t)*total_number_of_neurons));

}


void PoissonSpikingNeurons::reset_neurons() {

	SpikingNeurons::reset_neurons();

	CudaSafeCall(cudaMemcpy(d_rates, rates, sizeof(float)*total_number_of_neurons, cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemset(d_states, -1000.0f, sizeof(float)*total_number_of_neurons));
}


// void PoissonSpikingNeurons::set_custom_possion_rates() {
	
// }

void PoissonSpikingNeurons::set_threads_per_block_and_blocks_per_grid(int threads) {
	
	SpikingNeurons::set_threads_per_block_and_blocks_per_grid(threads);

}



__global__ void generate_random_states_kernal(unsigned int seed, curandState_t* d_states, size_t total_number_of_neurons);


void PoissonSpikingNeurons::generate_random_states() {
	
	printf("Generating input neuron random states\n");

	// generate_random_states_kernal<<<number_of_neuron_blocks_per_grid, threads_per_block>>>(42, d_states, total_number_of_neurons);

	// CudaCheckError();

	if (random_state_manager == NULL) {
		random_state_manager = new RandomStateManager();
		random_state_manager->set_up_random_states(128, 64, 9);
	}
}


__global__ void generate_random_states_kernal(unsigned int seed, curandState_t* d_states, size_t total_number_of_neurons) {
	int idx = threadIdx.x + blockIdx.x * blockDim.x;
	if (idx < total_number_of_neurons) {
		curand_init(seed, /* the seed can be the same for each core, here we pass the time in from the CPU */
					idx, /* the sequence number should be different for each core (unless you want all
							cores to get the same sequence of numbers for some reason - use thread id! */
 					0, /* the offset is how much extra we advance in the sequence for each call, can be 0 */
					&d_states[idx]);
	}
}


__global__ void poisson_update_membrane_potentials_kernal(curandState_t* d_states,
							float *d_rates,
							float *d_membrane_potentials_v,
							float timestep,
							size_t total_number_of_inputs);


void PoissonSpikingNeurons::update_membrane_potentials(float timestep) {

	// poisson_update_membrane_potentials_kernal<<<number_of_neuron_blocks_per_grid, threads_per_block>>>(random_state_manager->d_states,
	// 													d_rates,
	// 													d_membrane_potentials_v,
	// 													timestep,
	// 													total_number_of_neurons);

	poisson_update_membrane_potentials_kernal<<<random_state_manager->block_dimensions, random_state_manager->threads_per_block>>>(random_state_manager->d_states,
														d_rates,
														d_membrane_potentials_v,
														timestep,
														total_number_of_neurons);

	CudaCheckError();
}


__global__ void poisson_update_membrane_potentials_kernal(curandState_t* d_states,
							float *d_rates,
							float *d_membrane_potentials_v,
							float timestep,
							size_t total_number_of_inputs){

	 
	int t_idx = threadIdx.x + blockIdx.x * blockDim.x;
	int idx = t_idx;
	while (idx < total_number_of_inputs){

		// Creates random float between 0 and 1 from uniform distribution
		// d_states effectively provides a different seed for each thread
		// curand_uniform produces different float every time you call it
		float random_float = curand_uniform(&d_states[t_idx]);

		// if the randomnumber is less than the rate
		if (random_float < (d_rates[idx] * timestep)){

			// Puts membrane potential above default spiking threshold
			d_membrane_potentials_v[idx] = 35.0f;

		} 

		idx += blockDim.x * gridDim.x;

	}
	__syncthreads();
}

