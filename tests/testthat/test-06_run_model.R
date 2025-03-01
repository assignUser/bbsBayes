test_that("model_params()", {

  p <- stratify(by = "bbs_usgs", sample_data = TRUE, quiet = TRUE) %>%
    prepare_data(min_max_route_years = 2)

  p <- p$model_data

  for(i in seq_len(nrow(bbs_models))) {
    model <- bbs_models$model[i]
    if(model == "gam") n_knots <- 9 else n_knots <- NULL

    expect_silent(
      m <- model_params(
        model = model,
        n_strata = p$n_strata, year = p$year, n_counts = p$n_counts,
        heavy_tailed = TRUE,
        n_knots = n_knots,
        basis = "mgcv",
        use_pois = FALSE,
        calculate_nu = FALSE,
        calculate_log_lik = FALSE,
        calculate_CV = FALSE))
    n <- c("calc_nu", "heavy_tailed", "use_pois",
           "calc_log_lik", "calc_CV", "train", "test",
           "n_train", "n_test")

    if(model %in% c("gam", "gamye")) n <- c(n, "n_knots_year", "year_basis")
    if(model == "first_diff") n <- c(n, "fixed_year", "zero_betas",
                                     "Iy1", "n_Iy1", "Iy2", "n_Iy2")
    if(model == "slope") n <- c(n, "fixed_year")
    expect_named(m, n)

  }

})

test_that("create_init_def", {

  withr::local_seed(111)

  p <- stratify(by = "bbs_usgs", sample_data = TRUE, quiet = TRUE) %>%
    prepare_data(min_max_route_years = 2)

  p <- p$model_data


  for(i in seq_len(nrow(bbs_models))) {
    model <- bbs_models$model[i]
    if(model == "gam") n_knots <- 9 else n_knots <- NULL
    m <- append(p,
                model_params(model = model,
                             n_strata = p$n_strata, year = p$year,
                             n_counts = p$n_counts,
                             heavy_tailed = TRUE,
                             n_knots = n_knots,
                             basis = "mgcv",
                             use_pois = FALSE,
                             calculate_nu = FALSE,
                             calculate_log_lik = FALSE,
                             calculate_CV = FALSE))


    expect_silent(id <- create_init_def(bbs_models$model[i], bbs_models$variant[i],
                                        model_data = m, chains = 3)) %>%
      expect_type("list")

    expect_snapshot_value(id, style = "json2", tolerance = 0.0001)
  }
})

test_that("run_model", {

 skip("long")

  withr::local_seed(111)

  p <- stratify(by = "bbs_usgs", sample_data = TRUE, quiet = TRUE) %>%
    prepare_data(min_max_route_years = 2)

  sp <- prepare_spatial(load_map("bbs_cws"), p, quiet = TRUE)

  for(i in seq_len(nrow(bbs_models))) {

    expect_message(r <- run_model(p,
                                  model = bbs_models$model[i],
                                  model_variant = bbs_models$variant[i],
                                  spatial_data = sp,
                                  out_dir = ".", chains = 2,
                                  iter_sampling = 10, iter_warmup = 10,
                                  refresh = 0,
                                  seed = 111)) %>%
      # Catch all messages and notes
      suppressMessages() %>%
      suppressWarnings() %>%
      utils::capture.output()

    expect_type(r, "list")
    expect_named(r, c("model_fit", "non_zero_weight", "meta_data",
                      "meta_strata", "raw_data"))
    expect_s3_class(r$model_fit, "CmdStanMCMC")

    f <- paste0("BBS_STAN_", bbs_models$model[i], "_", bbs_models$variant[i],
                "_", Sys.Date(), c("-1.csv", "-2.csv", ".rds"))

    expect_true(all(file.exists(f)))
  }

  # Clean up
  unlink(list.files(test_path(), paste0("^BBS_STAN_(.)*_", Sys.Date()), full.names = TRUE))
})
