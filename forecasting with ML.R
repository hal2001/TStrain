rm(list = ls())
library(TSstudio)
library(lubridate)
library(dplyr)
data(USgas)


df <- data.frame(date = ymd(paste(floor(time(USgas)), cycle(USgas), "01", sep = "-")),
                 y = as.numeric(USgas))

ts_plot(df)

df$month <- factor(lubridate::month(df$date))
df$lag12 <- dplyr::lag(df$y, n = 12)
df$lag24 <- dplyr::lag(df$y, n = 24)
head(df)



ts_seasonal(df[, c("date", "y")], type = "all")

h <- 12

df$index <- 1:nrow(df)

train <- df[1:(nrow(df) - h),]
test <- df[(nrow(df) - h +1):nrow(df), ]

md1 <- lm(y ~ index, data = train)
summary(md1)
plot(df$index, df$y)
abline(md1)

test$y_lm1 <- predict(md1, newdata = test)
plot(test$index, test$y, type = "l")
lines(test$index, test$y_lm1, type = "l")

md2 <- lm(y ~ index + month, data = train)
summary(md2)

plot(train$index, train$y, type = "l")
lines(train$index, predict(md2, newdata = train), type = "l", col = "red")

test$y_lm2 <- predict(md2, newdata = test)
plot(test$index, test$y, type = "l")
lines(test$index, test$y_lm2, type = "l", col = "green")

md3 <- lm(y ~ index + month + lag12 + lag24, data = train)
summary(md3)

plot(train$index, train$y, type = "l")
lines(train$index, predict(md3, newdata = train), type = "l", col = "red")

test$y_lm3 <- predict(md3, newdata = test)
plot(test$index, test$y, type = "l")
lines(test$index, test$y_lm3, type = "l", col = "red")



library(h2o)

h2o.init(max_mem_size = "15g")

h2o.removeAll()
train_h <- as.h2o(train)
test_h <- as.h2o(test)
x <- c("index", "month", "lag12", "lag24")
y <- "y"

rf1 <- h2o.randomForest(
  training_frame = train_h,
  nfolds = 5,
  x = x,
  y = y,
  ntrees = 500,
  stopping_rounds = 5,
  score_each_iteration = TRUE,
  seed = 1234
)

summary(rf1)
h2o.varimp_plot(rf1)
h2o.performance(rf1, valid = T)

test_h$pred_rf <- h2o.predict(rf1, test_h)
test_1 <- as.data.frame(test_h)
plot(test_1$index, test_1$y, type = "l")
lines(test_1$index, test_1$pred_rf, type = "l", col = "red")
lines(test_1$index, test_1$y_lm3, type = "l", col = "green")


mape_lm3 <- mean(abs(test_1$y - test_1$y_lm3) / test_1$y)
mape_lm3
mape_rf <- mean(abs(test_1$y - test_1$pred_rf) / test_1$y)
mape_rf

gbm1 <- h2o.gbm(
  training_frame = train_h,
  nfolds = 10,
  x = x,
  y = y,
  max_depth = 20,
  distribution = "gaussian",
  ntrees = 500,
  learn_rate = 0.1,
  score_each_iteration = TRUE
)

summary(gbm1)
h2o.varimp_plot(gbm1)
h2o.performance(gbm1, valid = T)

test_h$pred_gbm  <- h2o.predict(gbm1, test_h)
test_1 <- as.data.frame(test_h)

mape_gbm <- mean(abs(test_1$y - test_1$pred_gbm) / test_1$y)
mape_gbm

plot(test_1$index, test_1$y, type = "l")
lines(test_1$index, test_1$pred_gbm, type = "l", col = "blue")
lines(test_1$index, test_1$pred_rf, type = "l", col = "red")
lines(test_1$index, test_1$y_lm3, type = "l", col = "green")

h2o.rm("gbm_depth")

hyper_parameters_depth = list(max_depth = seq(1,30,1) )
gbm_grid_depth <- h2o.grid(algorithm = "gbm",
                           training_frame = train_h,
                           nfolds = 5,
                           hyper_params = hyper_parameters_depth,
                           y = y,
                           x = x,
                           learn_rate = 0.05,
                           learn_rate_annealing = 0.99,
                           sample_rate = 0.8,
                           col_sample_rate = 0.8,
                           ntrees = 10000,
                           search_criteria = list(strategy = "Cartesian"),
                           stopping_rounds = 5,
                           stopping_tolerance = 1e-4,
                           stopping_metric = "RMSE",
                           score_tree_interval = 10,
                           grid_id = "gbm_depth",
                           seed = 1234)

gbm_depth_summary <- h2o.getGrid(grid_id = "gbm_depth",
                                 sort_by = "rmse",
                                 decreasing = FALSE)
gbm_depth_summary

topDepths <- gbm_depth_summary@summary_table$max_depth[1:5]
minDepths <- min(as.numeric(topDepths))
maxDepths <- max(as.numeric(topDepths))

gbm_depth_model <- h2o.getModel(gbm_depth_summary@model_ids[[1]])

summary(gbm_depth_model)
h2o.varimp_plot(gbm_depth_model)
h2o.performance(gbm1, valid = T)
h2o.performance(gbm_depth_model, valid = T)
test_h$pred_gbm_depth  <- h2o.predict(gbm_depth_model, test_h)
test_1 <- as.data.frame(test_h)

mape_gbm_grid <- mean(abs(test_1$y - test_1$pred_gbm_depth) / test_1$y)
mape_gbm_grid

plot(test_1$index, test_1$y, type = "l")
lines(test_1$index, test_1$pred_rf, type = "l", col = "red")
lines(test_1$index, test_1$y_lm3, type = "l", col = "purple")
lines(test_1$index, test_1$pred_gbm, col = "blue")
lines(test_1$index, test_1$pred_gbm_depth, col = "green")


# h2o.rm("gbm_final")
hyper_parameters <- list(
  max_depth = seq(minDepths,maxDepths,1),
  sample_rate = seq(0.2,1,0.01),
  col_sample_rate = seq(0.2,1,0.01),
  col_sample_rate_per_tree = seq(0.2,1,0.01),
  col_sample_rate_change_per_level = seq(0.9,1.1,0.01),
  min_rows = 2^seq(0,log2(nrow(train))-1,2),
  nbins = 2^seq(4,10,1),
  nbins_cats = 2^seq(4,12,1),
  min_split_improvement = c(0,1e-8,1e-6,1e-4),
  histogram_type = c("UniformAdaptive","QuantilesGlobal","RoundRobin")
)

search_criteria = list(
  strategy = "RandomDiscrete",
  max_runtime_secs = 4000,
  seed = 1234,
  stopping_rounds = 5,
  stopping_metric = "RMSE",
  stopping_tolerance = 1e-4
)
gbm_grid <- h2o.grid(algorithm = "gbm",
                     training_frame = train_h,
                     nfolds = 5,
                     y = y,
                     x = x,
                     hyper_params = hyper_parameters,
                     search_criteria = search_criteria,
                     learn_rate = 0.05,
                     learn_rate_annealing = 0.99,
                     ntrees = 10000,
                     stopping_rounds = 5,
                     stopping_tolerance = 1e-4,
                     stopping_metric = "RMSE",
                     score_tree_interval = 10,
                     grid_id = "gbm_final",
                     seed = 1234)

gbm_final_summary <- h2o.getGrid(grid_id = "gbm_final",
                                 sort_by = "rmse",
                                 decreasing = FALSE)

gbm_final_summary
gbm_final_model <- h2o.getModel(gbm_final_summary@model_ids[[1]])

summary(gbm_final_model)
h2o.varimp_plot(gbm_final_model)
h2o.performance(gbm1, valid = T)
h2o.performance(gbm_depth_model, valid = T)
h2o.performance(gbm_final_model, valid = T)
test_h$pred_gbm_final  <- h2o.predict(gbm_final_model, test_h)
test_1 <- as.data.frame(test_h)

mape_gbm_final <- mean(abs(test_1$y - test_1$pred_gbm_final) / test_1$y)
mape_gbm_final

plot(test_1$y, type = "l")
lines(test_1$pred_gbm, col = "blue")
lines(test_1$pred_gbm_depth, col = "green")
lines(test_1$pred_gbm_final, col = "orange")

gbm_cv <- do.call(h2o.gbm,
                  ## update parameters in place
                  {
                    p <- gbm_final_model@parameters
                    p$model_id = NULL          ## do not overwrite the original grid model
                    p$training_frame = df_full      ## use the full dataset
                    p$validation_frame = NULL  ## no validation frame
                    p$nfolds = 10               ## cross-validation
                    p
                  }
)

gbm_cv@model$cross_validation_metrics_summary
summary(gbm_cv)
h2o.varimp_plot(gbm_final_model)
h2o.performance(gbm1, valid = T)
h2o.performance(gbm_depth_model, valid = T)
h2o.performance(gbm_final_model, valid = T)
h2o.performance(gbm_cv, valid = T)
test_h$pred_gbm_cv  <- h2o.predict(gbm_cv, test_h)
test_1 <- as.data.frame(test_h)

mape_gbm_cv <- mean(abs(test_1$y - test_1$pred_gbm_cv) / test_1$y)
mape_gbm_cv

plot(test_1$y, type = "l")
lines(test_1$pred_gbm, col = "blue")
lines(test_1$pred_gbm_depth, col = "green")
lines(test_1$pred_gbm_final, col = "orange")
lines(test_1$pred_gbm_cv, col = "purple")

for(i in 1:5){
  gbm <- h2o.getModel(gbm_final_summary@model_ids[[i]])
  cvgbm <- do.call(h2o.gbm,
                   ## update parameters in place
                   {
                     p <- gbm@parameters
                     p$model_id = NULL          ## do not overwrite the original grid model
                     p$training_frame = df_full      ## use the full dataset
                     p$validation_frame = NULL  ## no validation frame
                     p$nfolds = 5               ## cross-validation
                     p
                   }
  )
  print(gbm@model_id)
  print(cvgbm@model$cross_validation_metrics_summary[6,])
}

test_1$pred_gbm_cv2 <-  NULL
k=10
for (i in 1:k) {
  gbm <- h2o.getModel(gbm_final_summary@model_ids[[i]])
  if (is.null(test_h$pred_gbm_cv2 )) test_h$pred_gbm_cv2  = h2o.predict(gbm, test_h)
  else test_h$pred_gbm_cv2  = test_h$pred_gbm_cv2  + h2o.predict(gbm, test_h)
}
test_h$pred_gbm_cv2 <- test_h$pred_gbm_cv2 / k

test_1 <- as.data.frame(test_h)
head(test_1$pred_gbm_cv2)

mape_gbm_cv2 <- mean(abs(test_1$y - test_1$pred_gbm_cv2 ) / test_1$y)
mape_gbm_cv2

plot(test_1$y, type = "l")
lines(test_1$pred_gbm, col = "blue")
lines(test_1$pred_gbm_depth, col = "green")
lines(test_1$pred_gbm_final, col = "orange")
lines(test_1$pred_gbm_cv, col = "brown")
lines(test_1$pred_gbm_cv2, col = "red")
lines(test_1$pred_rf_cv, col = "blue")



autoML1 <- h2o.automl(training_frame = train,
                      leaderboard_frame = valid,
                      x = x,
                      y = y,
                      max_runtime_secs = 300)