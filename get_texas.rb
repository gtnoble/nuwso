require 'csv'
require 'pry'

texas_lat_limits = p [25.0 + 50.0 / 60.0, 36.0 + 30.0 / 60.0]
texas_lon_limits = p [-(106.0 + 39.0 / 60.0) ,-(93.0 + 31.0 / 60.0)]

def within_limits?(limits, value)
  return ((value >= limits[0]) and (value <= limits[1]))
end

#binding.pry

CSV.open(ARGV[1], 
         "wb", 
          write_headers: true,
          headers: ["X", "Y", "Z"]) do |row_out|
  CSV.foreach(ARGV[0], headers: true) do |row_in|
    latitude = row_in["Y"].to_f
    longitude = row_in["X"].to_f
    value = row_in["Z"].to_f
    is_point_included = (within_limits?(texas_lat_limits, latitude) and 
                        within_limits?(texas_lon_limits, longitude) and
                        value != 0.0)

    #binding.pry
    row_out << [longitude, latitude, value] if is_point_included
  end
end
    

