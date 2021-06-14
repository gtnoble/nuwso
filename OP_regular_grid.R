library(fields)

scattered_op_points <- read.csv("data/Peak Overpressure vs. distance and burst height.csv")

log10pressure <- log10(scattered_op_points[,3])

op_thin_plate_spline_model <- Tps(scattered_op_points[,1:2], log10pressure)

xrange = seq(from = 0, to = max(scattered_op_points[,1]), length.out = 1000)
yrange = seq(from = 0, to = max(scattered_op_points[,2]), length.out = 1000)

grid_range = list(X = xrange, Y = yrange)

evaluated_grid = predictSurface(op_thin_plate_spline_model, 
                                 grid.list = grid_range, extrap = TRUE)

image(evaluated_grid$x, evaluated_grid$y, evaluated_grid$z)

evaluated_data_frame = expand.grid(grid_range)

evaluated_data_frame$Z = as.vector(evaluated_grid$z)

write.csv(evaluated_data_frame, 
          "data/log_10_peak_overpressure_psi vs horiz_distance and hob.csv")

