require 'set'
require 'fastcsv'
require 'csv'

class SparseGridInterpolant

  attr_reader :min_x, :min_y, :max_x, :max_y

  def initialize(sparse_grid_filename, has_leading_index: false)
    @sparse_grid = Hash.new

    x_coordinates = Set.new
    y_coordinates = Set.new

    if has_leading_index == true
      starting_col = 1
    else
      starting_col = 0
    end

    File.open(sparse_grid_filename) do |file|
      FastCSV.to_enum(:raw_parse, file).each_with_index do |row, index|
        
        unless index == 0

          xval = row[starting_col].to_f #row["X"]
          yval = row[starting_col + 1].to_f #["Y"]
          zval = row[starting_col + 2].to_f #["Z"]

          x_coordinates.add(xval)
          y_coordinates.add(yval)

          @sparse_grid[xval] = Hash.new if @sparse_grid[xval].nil?
          @sparse_grid[xval][yval] = zval unless zval == 0
        end
      end
    end

    @sparse_grid_x_coordinates = x_coordinates.to_a.sort
    @min_x = @sparse_grid_x_coordinates[0]
    @max_x = @sparse_grid_x_coordinates[-1]

    @sparse_grid_y_coordinates = y_coordinates.to_a.sort
    @min_y = @sparse_grid_y_coordinates[0]
    @max_y = @sparse_grid_y_coordinates[-1]

  end

  
  def interpolate(x, y)
    return nil if outside_grid?(x, y)
    ix2 = @sparse_grid_x_coordinates.bsearch_index {|x_upper| x_upper > x}
    ix1 = ix2 - 1
    x1 = @sparse_grid_x_coordinates[ix1]
    x2 = @sparse_grid_x_coordinates[ix2]

    iy2 = @sparse_grid_y_coordinates.bsearch_index {|y_upper| y_upper > y}
    iy1 = iy2 - 1
    y1 = @sparse_grid_y_coordinates[iy1]
    y2 = @sparse_grid_y_coordinates[iy2]

    weight_x1 = (x2 - x) / (x2 - x1) 
    weight_x2 = (x - x1) / (x2 - x1)
    fxy1 = weight_x1 * read_grid(x1, y1) + weight_x2 * read_grid(x2, y1)
    fxy2 = weight_x1 * read_grid(x1, y2) + weight_x2 * read_grid(x2, y2)

    weight_y1 = (y2 - y) / (y2 - y1)
    weight_y2 = (y - y1) / (y2 - y1)
    fxy = weight_y1 * fxy1 + weight_y2 * fxy2

    return fxy
  end

  private

  def read_grid(x, y)
    z = @sparse_grid[x][y]
    ! z.nil? ? z : 0
  end

  def outside_grid?(x, y)
    is_outside_x_limits = (x < @min_x) | (x > @max_x)
    is_outside_y_limits = (y < @min_y) | (y > @max_y)

    if (is_outside_y_limits | is_outside_x_limits)
      return(true)
    else
      return(false)
    end
  end

end

