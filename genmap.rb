require 'csv'
require 'set'
require 'pry'
require 'yaml'
require 'gsl'
require 'ruby-prof'
require 'fastcsv'

require_relative "interpolate.rb"

FEET_PER_METER = 3.28084
DEGREES_TO_RADIANS = Math::PI / 180


class Warhead
  attr_accessor :latitude, :longitude, :height_of_burst, :energy_yield

  def initialize(latitude, longitude, height_of_burst, energy_yield)
    @coordinates = {latitude: latitude.to_f, #decimal degrees
                    longitude: longitude.to_f} #decimal degrees 
    @height_of_burst = height_of_burst.to_f #meters
    @energy_yield = energy_yield.to_f #kilotons
  end

  NEGLIGIBLE_EFFECT_DISTANCE_FOR_1_KT = 9000.0 #meters at 0.1 psi overpressure
  ONE_KT_LOG10_OVERPRESSURE = SparseGridInterpolant.new(\
                            "data/1kt_log_10_peak_overpressure_psi vs horiz_distance hob.csv",
                            has_leading_index: true)
  
  def negligible_effect_distance 
    return (NEGLIGIBLE_EFFECT_DISTANCE_FOR_1_KT * (@energy_yield ** (1.0 / 3.0)))
  end
  
  def peak_overpressure(target_coordinates, planet = EARTH)
    horizontal_distance = planet.great_circle_distance(target_coordinates,
                                                       warhead_coodinates)
    horizontal_distance_feet = horizontal_distance * FEET_PER_METER
    scaled_horizontal_distance = horizontal_distance_feet / @energy_yield ** (1.0 / 3.0)
    height_of_burst_feet = @height_of_burst * FEET_PER_METER
    scaled_height_of_burst = height_of_burst_feet / @energy_yield ** (1.0 / 3.0)
    log10_overpressure = ONE_KT_LOG10_OVERPRESSURE.interpolate(scaled_horizontal_distance,
                                                               scaled_height_of_burst)
    unless log10_overpressure.nil?
      overpressure = 10 ** log10_overpressure
    else
      overpressure = 0
    end

    return overpressure
  end
end

class Planet
  def initialize(radius)
    @radius = radius
  end

  def great_circle_distance(target_coordinates, warhead_coordinates)

    warhead_lat_radians = warhead_coordinates[:latitude] * DEGREES_TO_RADIANS
    warhead_lon_radians = warhead_coordinates[:longitude] * DEGREES_TO_RADIANS
    target_lat_radians = target_coordinates[:latitude] * DEGREES_TO_RADIANS
    target_lon_radians = target_coordinates[:longitude] * DEGREES_TO_RADIANS

    delta_latitude = (target_lat_radians - warhead_lat_radians)
    delta_longitude = (target_lon_radians - warhead_lon_radians)

    central_angle = 2 * Math.asin(Math.sqrt(\
                                            Math.sin(delta_latitude / 2) ** 2 +
                                            Math.cos(warhead_lat_radians) *
                                            Math.cos(target_lat_radians) *
                                            Math.sin(delta_longitude / 2) ** 2))

    distance = @radius * central_angle 
    return distance
  end
end

EARTH_RADIUS = 6378E3 #m
EARTH = Planet.new(EARTH_RADIUS)

class Sampler


  def initialize(warheads, sd_scaling_factor, planet = EARTH random_seed = 1)
    @total_yield = warheads.map {|warhead| warhead.energy_yield}.sum
    @planet = planet

    @warheads = warheads.map do |warhead|
      {selection_probability: warhead.energy_yield / @total_yield,
       effect_angular_standard_deviation: negligible_effect_angle(warhead) *
                                          sd_scaling_factor, 
       latitude: warhead.latitude,
       longitude: warhead.longitude}
     end


    @is_more_than_one_warhead = warheads.length > 1
    if @is_more_than_one_warhead
      warhead_probabilities = @warheads.map do |warhead| 
        warhead[:selection_probability] 
      end
      warhead_probabilities_gsl_vector = GSL::Vector.alloc(warhead_probabilities)
      @warhead_sampling_distribution = GSL::Ran::Discrete.alloc(
                                       warhead_probabilities_gsl_vector)
    end

    @sample_random_number = GSL::Rng.alloc("mt19937", random_seed)
  end
  
  def select_warhead
    if @is_more_than_one_warhead
      sampled_warhead_index = @sample_random_number.discrete(@warhead_probabilities)
      return @warheads[sampled_warhead_index]
    else
      return(@warheads[0])
    end
  end

  def importance_sample
    warhead = select_warhead
    standard_deviation = warhead[:effect_angular_standard_deviation]
    
    delta_latitude = @sample_random_number.gaussian(standard_deviation)
    latitude_sample = delta_latitude + warhead[:latitude]
    delta_longitude  = @sample_random_number.gaussian(standard_deviation) 
    longitude_sample = delta_longitude + warhead[:longitude]
    
        
    return {latitude: latitude_sample, 
            longitude: longitude_sample}
  end

  def importance_weight(target_point)
    target_latitude = target_point[:latitude]
    target_longitude = target_point[:longitude]

    total_weight = @warheads.reduce(0) do |accumulated_weight, warhead|
      yield_weight = warhead[:selection_probability]

      standard_deviation = warhead[:effect_angular_standard_deviation]
      delta_latitude = target_latitude - warhead[:latitude]
      delta_longitude = target_longitude - warhead[:longitude]
      radial_weight = (GSL::Ran::gaussian_pdf(delta_latitude, standard_deviation)) *
                      (GSL::Ran::gaussian_pdf(delta_longitude, standard_deviation))

      (radial_weight) * (yield_weight) + (accumulated_weight)
    end

    return total_weight
  end

  def negligible_effect_angle(warhead) 
      equatorial_circumference = 2 * Math::PI * planet.radius
      negligible_effect_angle = warhead.negligible_effect_distance / 
                                equatorial_circumference * 360
      return negligible_effect_angle 
  end

end

class IntegratedEffect
  #Block accumulates destruction fraction
  def initialize(planet, random_seed = 1, &destructive_effect)
   @destructive_effect = destructive_effect
  end

  # Block passes target vulnerablility density
  def total_effect(warheads)

    fatality_estimate = 0
    number_of_integration_points = 1000
    1000.times do
      
      integrand_evaluation_point = importance_sample

      destruction_fraction = destructive_effect.call(warheads.map(&:peak_overpressure)) 

      vulnerability_density = yield(integrand_evaluation_point) 
      destroyed_vulnerability_density = vulnerability_density * destruction_fraction

      spherical_surface_factor =    planet.radius ** 2 *
                                    Math.cos(integrand_evaluation_point[:latitude] * 
                                             DEGREES_TO_RADIANS) *
                                    DEGREES_TO_RADIANS ** 2 /

      fatality_estimate +=  destroyed_vulnerability_density * 
                            spherical_surface_factor /
                            importance_weight(integrand_evaluation_point)) /
                            number_of_integration_points 

      end

    return fatality_estimate

  end

end

class OverpressureEffect

  def self.fatality_rate(overpressure)
    case overpressure
      
      when (2..5)
        fatality_rate = 0.05
      when (5..12)
        fatality_rate = 0.5
      when (12..)
        fatality_rate = 0.98
      else
        fatality_rate = 0
    end

    return fatality_rate 
  end

end

def population_density(pop_density_map, target_point)
    latitude = target_point[:latitude]
    longitude = target_point[:longitude]
    pop_density_per_m2 = pop_density_map.interpolate(longitude, latitude) / 1E6
    return pop_density_per_m2

end

  
#binding.pry
warheads = Array.new
CSV.foreach(ARGV[0], headers: true) do |row|
  warheads << Warhead.new(row["latitude"],
                          row["longitude"],
                          row["altitude"],
                          row["yield"])
end

pop_density_map = SparseGridInterpolant.new(ARGV[1])
puts "density map loaded"


