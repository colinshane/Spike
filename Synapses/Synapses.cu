//	Synapse Class C++
//	Synapse.cpp
//
//	Author: Nasir Ahmad
//	Date: 7/12/2015

#include "Synapses.h"
#include "../Helpers/CUDAErrorCheckHelpers.h"
#include "../Helpers/TerminalHelpers.h"

#include <algorithm> // for random shuffle
#include <curand.h>
#include <curand_kernel.h>


// Macro to get the gaussian prob
//	INPUT:
//			x = The pre-population input neuron position that is being checked
//			u = The post-population neuron to which the connection is forming (taken as mean)
//			sigma = Standard Deviation of the gaussian distribution
#define GAUS(distance, sigma) ( (1.0f/(sigma*(sqrt(2.0f*M_PI)))) * (exp(-1.0f * (pow((distance),(2.0f))) / (2.0f*(pow(sigma,(2.0f)))))) )

__global__ void compute_yes_no_connection_matrix_for_groups(bool * d_yes_no_connection_matrix, int prestart, int preend, int poststart, int postend, int pre_width, int post_width, float sigma, int total_pre_neurons, int total_post_neurons);

// Synapses Constructor
Synapses::Synapses() {

	// Initialise my parameters
	// Variables;
	total_number_of_synapses = 0;
	temp_number_of_synapses_in_last_group = 0;

	original_synapse_indices = NULL;

	// Full Matrices
	presynaptic_neuron_indices = NULL;
	postsynaptic_neuron_indices = NULL;
	synaptic_efficacies_or_weights = NULL;

	temp_presynaptic_neuron_indices = NULL;
	temp_postsynaptic_neuron_indices = NULL;
	temp_synaptic_efficacies_or_weights = NULL;

	d_presynaptic_neuron_indices = NULL;
	d_postsynaptic_neuron_indices = NULL;
	d_synaptic_efficacies_or_weights = NULL;

	// On construction, seed
	srand(42);	// Seeding the random numbers
}

// Synapses Destructor
Synapses::~Synapses() {
	// Just need to free up the memory
	// Full Matrices
	free(presynaptic_neuron_indices);
	free(postsynaptic_neuron_indices);
	free(synaptic_efficacies_or_weights);

	CudaSafeCall(cudaFree(d_presynaptic_neuron_indices));
	CudaSafeCall(cudaFree(d_postsynaptic_neuron_indices));
	CudaSafeCall(cudaFree(d_synaptic_efficacies_or_weights));

}

// Setting personal STDP parameters
void Synapses::SetSTDP(float w_max_new,
				float a_minus_new,
				float a_plus_new,
				float tau_minus_new,
				float tau_plus_new){
	// Set the values
	stdp_vars.w_max = w_max_new;
	stdp_vars.a_minus = a_minus_new;
	stdp_vars.a_plus = a_plus_new;
	stdp_vars.tau_minus = tau_minus_new;
	stdp_vars.tau_plus = tau_plus_new;
}

// Connection Detail implementation
//	INPUT:
//		Pre-neuron population ID
//		Post-neuron population ID
//		An array of the exclusive sum of neuron populations
//		CONNECTIVITY_TYPE (Constants.h)
//		2 number float array for weight range
//		2 number float array for delay range
//		Boolean value to indicate if population is STDP based
//		Parameter = either probability for random synapses or S.D. for Gaussian
void Synapses::AddGroup(int presynaptic_group_id, 
						int postsynaptic_group_id, 
						Neurons * neurons,
						Neurons * input_neurons,
						int connectivity_type,
						float weight_range[2],
						int delay_range[2],
						bool stdp_on,
						connectivity_parameters_struct * connectivity_params,
						float parameter,
						float parameter_two) {
	
	// Find the right set of indices
	// Take everything in 2D

	printf("Adding synapse group...\n");
	printf("presynaptic_group_id: %d\n", presynaptic_group_id);
	printf("postsynaptic_group_id: %d\n", postsynaptic_group_id);

	int* last_neuron_indices_for_neuron_groups = neurons->last_neuron_indices_for_each_group;
	int* last_neuron_indices_for_input_neuron_groups = input_neurons->last_neuron_indices_for_each_group;

	int * presynaptic_group_shape;
	int * postsynaptic_group_shape;

	int group_type_factor = 1;
	int group_type_component = 0;
	int prestart = 0;
	int preend = 0;
	int poststart = 0;

	// Calculate presynaptic group start and end indices
	// Also assign presynaptic group shape
	if (presynaptic_group_id < 0) { // If presynaptic group is Input group

		if (stdp_on == true) print_message_and_exit("Plasticity between input neurons and model neurons is not currently supported.");

		group_type_factor = -1;
		group_type_component = -1;
		presynaptic_group_shape = input_neurons->group_shapes[-1*presynaptic_group_id - 1];

		if (presynaptic_group_id < -1){
			prestart = last_neuron_indices_for_input_neuron_groups[-1*presynaptic_group_id - 2];
		}
		preend = last_neuron_indices_for_input_neuron_groups[-1*presynaptic_group_id - 1];

	} else {

		presynaptic_group_shape = neurons->group_shapes[presynaptic_group_id];

		if (presynaptic_group_id > 0){
			prestart = last_neuron_indices_for_neuron_groups[presynaptic_group_id - 1];
		}
		preend = last_neuron_indices_for_neuron_groups[presynaptic_group_id];

	}

	// Calculate postsynaptic group start and end indices
	// Also assign postsynaptic group shape
	if (postsynaptic_group_id < 0) { // If presynaptic group is Input group EXIT

		print_message_and_exit("Input groups cannot be a postsynaptic neuron group.");

	} else if (postsynaptic_group_id >= 0){
		postsynaptic_group_shape = neurons->group_shapes[postsynaptic_group_id];

		if (postsynaptic_group_id == 0) {
			poststart = 0;
		} else {
			poststart = last_neuron_indices_for_neuron_groups[postsynaptic_group_id - 1];
		}
		
	}
	int postend = last_neuron_indices_for_neuron_groups[postsynaptic_group_id];

	const char * presynaptic_group_type_string = (presynaptic_group_id < 0) ? "input_neurons" : "neurons";
	printf("Presynaptic neurons start index: %d (%s)\n", prestart, presynaptic_group_type_string);
	printf("Presynaptic neurons end index: %d (%s)\n", preend, presynaptic_group_type_string);
	printf("Postsynaptic neurons start index: %d (neurons)\n", poststart);
	printf("Postsynaptic neurons end index: %d (neurons)\n", postend);


	int original_number_of_synapses = total_number_of_synapses;

	// Carry out the creation of the connectivity matrix
	switch (connectivity_type){
            
		case CONNECTIVITY_TYPE_ALL_TO_ALL:
		{
            
            int increment = (preend-prestart)*(postend-poststart);
            this->increment_number_of_synapses(increment);
            
			// If the connectivity is all_to_all
			for (int i = prestart; i < preend; i++){
				for (int j = poststart; j < postend; j++){
					// Index
					int idx = original_number_of_synapses + (i-prestart) + (j-poststart)*(preend-prestart);
					// Setup Synapses
					presynaptic_neuron_indices[idx] = group_type_factor*i + group_type_component;
					postsynaptic_neuron_indices[idx] = j;
				}
			}
			break;
		}
		case CONNECTIVITY_TYPE_ONE_TO_ONE:
		{
            int increment = (preend-prestart);
            this->increment_number_of_synapses(increment);
            
			// If the connectivity is one_to_one
			if ((preend-prestart) != (postend-poststart)) print_message_and_exit("Unequal populations for one_to_one.");
			// Create the connectivity
			for (int i = 0; i < (preend-prestart); i++){
				presynaptic_neuron_indices[original_number_of_synapses + i] = group_type_factor*(prestart + i) + group_type_component;
				postsynaptic_neuron_indices[original_number_of_synapses + i] = poststart + i;
			}

			break;
		}
		case CONNECTIVITY_TYPE_RANDOM: //JI DO
		{
			// If the connectivity is random
			// Begin a count
			for (int i = prestart; i < preend; i++){
				for (int j = poststart; j < postend; j++){
					// Probability of connection
					float prob = ((float)rand() / (RAND_MAX));
					// If it is within the probability range, connect!
					if (prob < parameter){
						
						this->increment_number_of_synapses(1);

						// Setup Synapses
						presynaptic_neuron_indices[total_number_of_synapses - 1] = group_type_factor*i + group_type_component;
						postsynaptic_neuron_indices[total_number_of_synapses - 1] = j;
					}
				}
			}
			break;
		}
		
		case CONNECTIVITY_TYPE_GAUSSIAN: // 1-D or 2-D
		{

			float sigma = parameter;

			// For gaussian connectivity, the shape of the layers matters.
			// If we desire a given number of neurons, we must scale the gaussian
			float gaussian_scaling_factor = 1.0f;
			if (parameter_two != 0.0f){
				gaussian_scaling_factor = 0.0f;
				int pre_x = presynaptic_group_shape[0] / 2;
				int pre_y = presynaptic_group_shape[1] / 2;
				for (int i = 0; i < postsynaptic_group_shape[0]; i++){
					for (int j = 0; j < postsynaptic_group_shape[1]; j++){
						// Post XY
						int post_x = i;
						int post_y = j;
						// Distance
						float distance = pow((pow((float)(pre_x - post_x), 2.0f) + pow((float)(pre_y - post_y), 2.0f)), 0.5f);
						// Gaussian Probability
						gaussian_scaling_factor += GAUS(distance, sigma);
					}
				}
				// Multiplying the gaussian scaling factor by the number of synapses you require:
				gaussian_scaling_factor = gaussian_scaling_factor / parameter_two;
			}

			int threads = 512;
			dim3 threads_per_block = dim3(threads);
			int total_number_of_neuron_pairs = (preend - prestart) * (postend - poststart);
			int number_of_neuron_pair_blocks = (total_number_of_neuron_pairs + threads) / threads;
			dim3 number_of_neuron_pair_blocks_per_grid = dim3(number_of_neuron_pair_blocks);

			int total_pre_neurons = preend - prestart;
			int total_post_neurons = postend - poststart;
			dim3 neuron_pair_block_dimensions = dim3((total_pre_neurons + threads)/threads, (total_post_neurons + threads)/threads);

			bool * d_yes_no_connection_matrix;
			CudaSafeCall(cudaMalloc((void **)&d_yes_no_connection_matrix, sizeof(int)*total_number_of_neuron_pairs));
			compute_yes_no_connection_matrix_for_groups<<<neuron_pair_block_dimensions, threads_per_block>>>(d_yes_no_connection_matrix, prestart, preend, poststart, postend, presynaptic_group_shape[0], postsynaptic_group_shape[0], sigma, total_pre_neurons, total_post_neurons);
			bool * yes_no_connection_matrix = (bool *)malloc(total_number_of_neuron_pairs*sizeof(bool));
			CudaSafeCall(cudaMemcpy(yes_no_connection_matrix, d_yes_no_connection_matrix, sizeof(bool)*total_number_of_neuron_pairs, cudaMemcpyDeviceToHost));

			// Running through our neurons
			//CUDARISE THIS!! VERY SLOW!!!
			for (int k = 0; k < connectivity_params->max_number_of_connections_per_pair; k++){
				for (int i = prestart; i < preend; i++){
					for (int j = poststart; j < postend; j++){
						// // Probability of connection
						// float prob = ((float) rand() / (RAND_MAX));
						// // Get the relative distance from the two neurons
						// // Pre XY
						// int pre_x = (i-prestart) % presynaptic_group_shape[0];
						// int pre_y = floor((float)(i-prestart) / presynaptic_group_shape[0]);
						// // Post XY
						// int post_x = (j-poststart) % postsynaptic_group_shape[0];
						// int post_y = floor((float)(j-poststart) / postsynaptic_group_shape[0]);

						// // Distance
						// float distance = sqrt((pow((float)(pre_x - post_x), 2.0f) + pow((float)(pre_y - post_y), 2.0f)));
						// // If it is within the probability range, connect!
						// if (prob <= ((GAUS(distance, sigma)) / gaussian_scaling_factor)){
						if (yes_no_connection_matrix[i*total_pre_neurons + j]) {
							
							this->increment_number_of_synapses(1);

							// Setup Synapses
							presynaptic_neuron_indices[total_number_of_synapses - 1] = group_type_factor*i + group_type_component;
							postsynaptic_neuron_indices[total_number_of_synapses - 1] = j;
						}
					}
				}
			}
			break;
		}
		case CONNECTIVITY_TYPE_IRINA_GAUSSIAN: // 1-D only
		{
			// Getting the population sizes
			int in_size = preend - prestart;
			int out_size = postend - poststart;
			// Diagonal Width value
			float diagonal_width = parameter;
			// Irina's application of some sparse measure
			float in2out_sparse = 0.67f*0.67f;
			// Irina's implementation of some kind of stride
			int dist = 1;
			if ( (float(out_size)/float(in_size)) > 1.0f ){
				dist = int(out_size/in_size);
			}
			// Irina's version of sigma
			double sigma = dist*diagonal_width;
			// Number of synapses to form
			int conn_num = int((sigma/in2out_sparse));
			int conn_tgts = 0;
			int temp = 0;
			// Running through the input neurons
			for (int i = prestart; i < preend; i++){
				double mu = int(float(dist)/2.0f) + (i-prestart)*dist;
				conn_tgts = 0;
				while (conn_tgts < conn_num) {
					temp = int(randn(mu, sigma));
					if ((temp >= 0) && (temp < out_size)){
						
						this->increment_number_of_synapses(1);

						// Setup the synapses:
						// Setup Synapses
						presynaptic_neuron_indices[total_number_of_synapses - 1] = group_type_factor*i + group_type_component;
						postsynaptic_neuron_indices[total_number_of_synapses - 1] = poststart + temp;

						// Increment conn_tgts
						++conn_tgts;
					}
				}
			}
			break;
		}
		case CONNECTIVITY_TYPE_SINGLE:
		{
			// If we desire a single connection
			this->increment_number_of_synapses(1);

			// Setup Synapses
			presynaptic_neuron_indices[original_number_of_synapses] = group_type_factor * (prestart + int(parameter)) + group_type_component;
			postsynaptic_neuron_indices[original_number_of_synapses] = poststart + int(parameter_two);

			break;
		}
		default:
		{
			print_message_and_exit("Unknown Connection Type.");
			break;
		}
	}

	temp_number_of_synapses_in_last_group = total_number_of_synapses - original_number_of_synapses;

	printf("%d new synapses added.\n\n", temp_number_of_synapses_in_last_group);

	for (int i = original_number_of_synapses; i < total_number_of_synapses; i++){
		// Setup Weights
		if (weight_range[0] == weight_range[1]) {
			synaptic_efficacies_or_weights[i] = weight_range[0];
		} else {
			float rndweight = weight_range[0] + (weight_range[1] - weight_range[0])*((float)rand() / (RAND_MAX));
			synaptic_efficacies_or_weights[i] = rndweight;
		}

		original_synapse_indices[i] = i;

	}


}

void Synapses::increment_number_of_synapses(int increment) {

	total_number_of_synapses += increment;

	presynaptic_neuron_indices = (int*)realloc(presynaptic_neuron_indices, total_number_of_synapses * sizeof(int));
    postsynaptic_neuron_indices = (int*)realloc(postsynaptic_neuron_indices, total_number_of_synapses * sizeof(int));
    synaptic_efficacies_or_weights = (float*)realloc(synaptic_efficacies_or_weights, total_number_of_synapses * sizeof(float));
    original_synapse_indices = (int*)realloc(original_synapse_indices, total_number_of_synapses * sizeof(int));
}


void Synapses::allocate_device_pointers() {

	CudaSafeCall(cudaMalloc((void **)&d_presynaptic_neuron_indices, sizeof(int)*total_number_of_synapses));
	CudaSafeCall(cudaMalloc((void **)&d_postsynaptic_neuron_indices, sizeof(int)*total_number_of_synapses));
	CudaSafeCall(cudaMalloc((void **)&d_synaptic_efficacies_or_weights, sizeof(float)*total_number_of_synapses));

	CudaSafeCall(cudaMemcpy(d_presynaptic_neuron_indices, presynaptic_neuron_indices, sizeof(int)*total_number_of_synapses, cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemcpy(d_postsynaptic_neuron_indices, postsynaptic_neuron_indices, sizeof(int)*total_number_of_synapses, cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemcpy(d_synaptic_efficacies_or_weights, synaptic_efficacies_or_weights, sizeof(float)*total_number_of_synapses, cudaMemcpyHostToDevice));

}

// Provides order of magnitude speedup for LIF (All to all atleast). 
// Because all synapses contribute to current_injection on every iteration, having all threads in a block accessing only 1 or 2 positions in memory causing massive slowdown.
// Randomising order of synapses means that each block is accessing a larger number of points in memory.
void Synapses::shuffle_synapses() {

	std::random_shuffle(&original_synapse_indices[0], &original_synapse_indices[total_number_of_synapses]);

	temp_presynaptic_neuron_indices = (int *)malloc(total_number_of_synapses*sizeof(int));
	temp_postsynaptic_neuron_indices = (int *)malloc(total_number_of_synapses*sizeof(int));
	temp_synaptic_efficacies_or_weights = (float *)malloc(total_number_of_synapses*sizeof(float));
	
	for(int i = 0; i < total_number_of_synapses; i++) {

		temp_presynaptic_neuron_indices[i] = presynaptic_neuron_indices[original_synapse_indices[i]];
		temp_postsynaptic_neuron_indices[i] = postsynaptic_neuron_indices[original_synapse_indices[i]];
		temp_synaptic_efficacies_or_weights[i] = synaptic_efficacies_or_weights[original_synapse_indices[i]];

	}

	presynaptic_neuron_indices = temp_presynaptic_neuron_indices;
	postsynaptic_neuron_indices = temp_postsynaptic_neuron_indices;
	synaptic_efficacies_or_weights = temp_synaptic_efficacies_or_weights;

}




void Synapses::set_threads_per_block_and_blocks_per_grid(int threads) {
	
	threads_per_block.x = threads;

	int number_of_synapse_blocks = (total_number_of_synapses + threads) / threads;
	number_of_synapse_blocks_per_grid.x = number_of_synapse_blocks;

	printf("number_of_synapse_blocks_per_grid.x: %d\n\n", number_of_synapse_blocks_per_grid.x);
}


__global__ void compute_yes_no_connection_matrix_for_groups(bool * d_yes_no_connection_matrix, int prestart, int preend, int poststart, int postend, int pre_width, int post_width, float sigma, int total_pre_neurons, int total_post_neurons) {
	
	int idx_pre = threadIdx.x + blockIdx.x * blockDim.x;
	int idx_post = threadIdx.y + blockIdx.y * blockDim.y;

	if ((idx_pre < total_pre_neurons) && (idx_post < total_post_neurons)) {

		unsigned int seed = 9;
		curandState_t state;
		curand_init(seed, /* the seed can be the same for each core, here we pass the time in from the CPU */
					idx_pre * total_pre_neurons + idx_post, /* the sequence number should be different for each core (unless you want all
							cores to get the same sequence of numbers for some reason - use thread id! */
 					0, /* the offset is how much extra we advance in the sequence for each call, can be 0 */
					&state);

		float prob = curand_uniform(&state);

		// Get the relative distance from the two neurons
		// Pre XY
		int pre_x = idx_pre % pre_width;
		int pre_y = floor((float)(idx_pre) / pre_width);
		// Post XY
		int post_x = idx_post % post_width;
		int post_y = floor((float)(idx_post) / post_width);

		// float distance = sqrt((pow((float)(pre_x - post_x), 2.0f) + pow((float)(pre_y - post_y), 2.0f)));
		float distance = norm3df((float)(pre_x - post_x), (float)(pre_y - post_y), 0);

		float gaussian_value = (1.0f/(sigma*(sqrtf(2.0f*M_PI)))) * (expf(-1.0f * (powf((distance),(2.0f))) / (2.0f*(powf(sigma,(2.0f))))));

		if (prob < gaussian_value) {
			d_yes_no_connection_matrix[idx_pre * total_pre_neurons + idx_post] = false;
		} else {
			d_yes_no_connection_matrix[idx_pre * total_pre_neurons + idx_post] = true;
		}

	}
}



// An implementation of the polar gaussian random number generator which I need
double randn (double mu, double sigma)
{
  double U1, U2, W, mult;
  static double X1, X2;
  static int call = 0;

  if (call == 1)
    {
      call = !call;
      return (mu + sigma * (double) X2);
    }

  do
    {
      U1 = -1 + ((double) rand () / RAND_MAX) * 2;
      U2 = -1 + ((double) rand () / RAND_MAX) * 2;
      W = pow (U1, 2) + pow (U2, 2);
    }
  while (W >= 1 || W == 0);

  mult = sqrt ((-2 * log (W)) / W);
  X1 = U1 * mult;
  X2 = U2 * mult;

  call = !call;

  return (mu + sigma * (double) X1);
}