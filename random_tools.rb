require 'gsl'
require 'pry'

module RandomTools
  class VectorRandomVariable
    def initialize(length, seed = 1, quasirandom: false)
      unless quasirandom
        random_number_generator = GSL::Rng.alloc("mt19937", seed)

        @get_random_vector = Proc.new do
          (1..length).map {|x| random_number_generator.uniform}
        end

        @reset_generator = Proc.new {random_number_generator.set(seed)}

      else 
        quasirandom_generator = GSL::QRng.alloc("sobol", length)
        random_vector = GSL::Vector.alloc(length)

        @get_random_vector = Proc.new do
          quasirandom_generator.get(random_vector)
          random_vector.to_a
        end

        @reset_generator = Proc.new {quasirandom_generator.init}
      end
    end

    def get_vector
      @get_random_vector.call
    end

    def reset
      @reset_generator.call
    end

  end

  class DiscreteDistribution
    def initialize(object_probabilities)
      probabilities = object_probabilities.keys
      objects = object_probabilities.values

      sum_probabilities = probabilities.sum
      normalized_probabilities = probabilities.map do |prob| 
        prob / sum_probabilities
      end

      cumulative_probability = 0
      probability_masses = normalized_probabilities.map do |probability|
        cumulative_probability += probability
      end

      @object_probability_mass = probability_masses.zip(objects).to_h
    end

    def inverse_pmf(x)
      output_object_key = @object_probability_mass.keys.bsearch do |probability_mass| 
        x <= probability_mass
      end

      object = @object_probability_mass[output_object_key]
      return object
    end
  end

  class RunningStats
    def initialize(initial_sample)
      @accumulated_sum = initial_sample
      @n = 1.0
      @sum_squares = 0.0
      @mean = initial_sample

    end

    def update(next_sample)
        @accumulated_sum += next_sample
        @n += 1.0
        previous_mean = @mean
        @mean = @accumulated_sum / @n
        previous_sum_squares = @sum_squares

        @sum_squares = previous_sum_squares + 
                       (next_sample - previous_mean) * 
                       (next_sample - mean)

    end

    def sample_variance
      @sum_squares / (@n - 1)
    end

    def population_variance
      @sum_squares / @n
    end

    def mean
      @mean
    end

    def sample_standard_deviation
      Math.sqrt(sample_variance)
    end

    def standard_error
      sample_standard_deviation / Math.sqrt(@n)
    end

  end

  
end

binding.pry 
