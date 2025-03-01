#' Fetch Breeding Bird Survey dataset
#'
#' \code{fetch_bbs_data} uses File Transfer Protocol (FTP) to fetch Breeding Bird
#'  Survey data from the United States Geological Survey (USGS) FTP site. This
#'  is the raw data that is uploaded to the site before any analyses are performed.
#'  A package-specific directory is created on the user's computer (see documentation of
#'  \code{rappdirs::appdir} for details of where this directory lives), and the BBS
#'  data is saved to that directory for use by other functions.
#'  Before downloading any data, the user must thoroughly read through the terms
#'  and conditions of the user of the data and type the word "yes" to agree.
#'
#' @param level A string, either "state" or "stop", specifying which counts to
#' fetch. Defaults to "state", which provides counts beginning in 1966,
#' aggregated in five bins, each of which contains cumulative counts from 10 of
#' the 50 stops along a route. Specifying "stop" provides stop-level data
#' beginning in 1997, which includes counts for each stop along routes
#' individually. Note that stop-level data is not currently supported by
#' the modeling utilities in bbsBayes.
#' @param release Integer: what yearly release is desired? options are 2022 (default including data through 2021 field season) or 2020 (including data through 2019)
#' @param quiet Logical: should progress bars be suppressed? Defaults to FALSE
#' @param force Logical: if BBS data already exists on computer, should it be overwritten? Defaults to FALSE
#'
#'
#' @return None
#'

fetch_bbs_data_orig <- function(level = "state",
                           release = 2022,
                           quiet = FALSE,
                           force = FALSE)
{
  if (!level %in% c('state', 'stop')) {
    stop("Invalid level argument: level must be one of 'state' or 'stop'.")
  }

  stopifnot(is.logical(quiet))

  # Print Terms of Use
  terms <- readChar(system.file(paste0("data-terms-",release),
                                package = "bbsBayes"),
                    file.info(system.file(paste0("data-terms-",release),
                                          package = "bbsBayes"))$size)

  cat(terms)

  agree <- readline(prompt = "Type \"yes\" (without quotes) to agree: ")

  if (agree != "yes")
  {
    return(NULL)
  }

  bbs_dir <- rappdirs::app_dir(appname = "bbsBayes")

  if (isFALSE(file.exists(bbs_dir$data())))
  {
    message(paste0("Creating data directory at ", bbs_dir$data()))
    dir.create(bbs_dir$data(), recursive = TRUE)
  }else
  {
    message(paste0("Using data directory at ", bbs_dir$data()))
  }

  if (level == "state")
  {
    if (file.exists(paste0(bbs_dir$data(), "/bbs_raw_data.RData")) &
        isFALSE(force))
    {
      warning("BBS state-level data file already exists. Use \"force = TRUE\" to overwrite.")
      return()
    }
  }else if (level == "stop")
  {
    if (file.exists(paste0(bbs_dir$data(), "/bbs_stop_data.RData")) &
        isFALSE(force))
    {
      warning("BBS stop-level data file already exists. Use \"force = TRUE\" to overwrite.")
      return()
    }
  }

  if (!isTRUE(quiet))
  {
    message("Connecting to USGS ScienceBase...", appendLF = FALSE)
  }

  connection <- sbtools::item_get(sb_id = get_sb_id(rel_date = release))
  if (!is.null(connection))
  {
    if (!isTRUE(quiet))
    {
      message("Connected!")
    }
  }

  bird <- get_counts_orig(level = level, quiet = quiet, sb_conn = connection)

  ################################################################
  # Route List Data
  ################################################################
  if (!isTRUE(quiet))
  {
    message("Downloading route data (Task 2/3)")
    pb <- progress::progress_bar$new(
      format = "\r[:bar] :percent eta: :eta",
      clear = FALSE,
      total = 9,
      width = 100)
    pb$tick(0)
  }

  temp <- tempdir()
  if(release == 2020){
    rtsfl <- "routes.zip" # if necessary because file name changed between 2020 and 2022 releases
  }else{
    rtsfl <- "Routes.zip"
  }
  full_path <- sbtools::item_file_download(sb_id = connection,
                                           names = rtsfl,
                                           destinations = file.path(temp, rtsfl))
  tick(pb, quiet)

  routes <- utils::read.csv(utils::unzip(zipfile = full_path,
                                         exdir = temp),
                            stringsAsFactors = FALSE,
                            fileEncoding = get_encoding())
  unlink(temp)
  tick(pb, quiet)

  # removes the off-road and water routes, as well as non-random and mini-routes
  routes <- routes[routes$RouteTypeDetailID == 1 & routes$RouteTypeID == 1, ]
  routes$Stratum <- NULL
  tick(pb, quiet)

  ################################################################
  # Weather Data
  ################################################################

  temp <- tempdir()
  full_path <- sbtools::item_file_download(sb_id = connection,
                                           names = "Weather.zip",
                                           destinations = file.path(temp, "Weather.zip"))
  tick(pb, quiet)

  weather <- utils::read.csv(utils::unzip(zipfile = full_path,
                                          exdir = temp),
                             stringsAsFactors = FALSE)
  unlink(temp)
  tick(pb, quiet)

  # removes the off-road and water routes, as well as non-random and mini-routes
  weather <- weather[weather$RunType == 1, ]
  tick(pb, quiet)

  # merge weather and routes
  # removes some rows from weather that are associated with the removed
  #   routes above (mini-routes etc.)
  route <- merge(routes, weather, by = c("CountryNum","StateNum","Route"))
  names(route)[tolower(names(route)) == "countrynum"] <- "countrynum"
  names(route)[tolower(names(route)) == "statenum"] <- "statenum"
  tick(pb, quiet)

  # Add region and BCR information to route and bird data frames
  regs <- utils::read.csv(system.file("data-import",
                                      "regs.csv",
                                      package="bbsBayes"),
                          stringsAsFactors = FALSE)
  tick(pb, quiet)

  # merge route data into the bird count data frame
  route <- merge(route, regs, by = c("countrynum", "statenum"))
  unique_routes <- unique(route[, c("BCR", "statenum", "Route", "countrynum")])
  bird <- merge(bird, unique_routes, by = c("statenum", "Route", "countrynum"))
  tick(pb, quiet)

  ################################################################
  # Species Data
  ################################################################

  if (!isTRUE(quiet))
  {
    message("Downloading species data (Task 3/3)")
    pb <- progress::progress_bar$new(
      format = "\r[:bar] :percent eta: :eta",
      clear = FALSE,
      total = 4,
      width = 100)
    pb$tick(0)
  }

  temp <- tempfile()
  full_path <- sbtools::item_file_download(sb_id = connection,
                                           names = "SpeciesList.txt",
                                           destinations = temp)
  tick(pb, quiet)

  if(release == 2022){lskip <- 14} #silly differences in file structure
  if(release == 2020){lskip <- 11}



  species <- utils::read.fwf(temp, skip = lskip, strip.white = TRUE, header = FALSE,
                             colClasses = c("integer",
                                            "character",
                                            "character",
                                            "character",
                                            "character",
                                            "character",
                                            "character",
                                            "character",
                                            "character"),
                             widths = c(6, -1, 5, -1, 50, -1, 50, -1, 50, -1,
                                        50, -1, 50, -1, 50, -1, 50),
                             fileEncoding = get_encoding())
  unlink(temp)
  tick(pb, quiet)

  names(species) <- c("seq","aou","english","french","spanish","order","family","genus","species")
  tick(pb, quiet)

  # this reads in the USGS BBS ftp site species file
  species[, "sp.bbs"] <- as.integer(as.character(species[, "aou"]))
  tick(pb, quiet)

  bbs_data <- list(bird = bird,
                   route = route,
                   species = species)

  # temp <- tempfile()
  # utils::download.file(paste0(base_url(), "SpeciesList.txt"), temp, quiet = TRUE)
  # tick(pb, quiet)
  # species <- utils::read.fwf(temp, skip = 10, strip.white = TRUE, header = FALSE,
  #                            colClasses = c("integer",
  #                                           "character",
  #                                           "character",
  #                                           "character",
  #                                           "character",
  #                                           "character",
  #                                           "character",
  #                                           "character",
  #                                           "character"),
  #                            widths = c(6, -1, 5, -1, 50, -1, 50, -1, 50, -1,
  #                                       50, -1, 50, -1, 50, -1, 50),
  #                     fileEncoding = "iso-8859-1")
  # unlink(temp)
  # tick(pb, quiet)

  #species <- species[, -c(4, 5)] # remove french and spanish name
  # names(species) <- c("seq","aou","english","french","spanish","order","family","genus","species")
  # tick(pb, quiet)

  # # this reads in the USGS BBS ftp site species file
  # species[, "sp.bbs"] <- as.integer(as.character(species[, "aou"]))
  # tick(pb, quiet)
  #
  #   bbs_data <- list(bird = bird,
  #                    route = route,
  #                    species = species)

  if (level == "state")
  {
    message(paste0("Saving BBS data to ", bbs_dir$data()))
    save(bbs_data, file = paste0(bbs_dir$data(), "/bbs_raw_data.RData"))
  }else if (level == "stop")
  {
    message(paste0("Saving BBS data to ", bbs_dir$data()))
    save(bbs_data, file = paste0(bbs_dir$data(), "/bbs_stop_data.RData"))
  }

}


get_counts_orig <- function(level, quiet, sb_conn) {
  if (level == "state") {
    count_zip <- "States.zip"
  }
  if (level == "stop") {
    count_zip <- "50-StopData.zip"
  }

  dir_listing_csv <- system.file("data-import",
                                 paste0(level, "-dir.csv"),
                                 package = "bbsBayes")
  bird_count_filenames <- utils::read.csv(dir_listing_csv)

  if (!isTRUE(quiet)) {
    message("Downloading count data (Task 1/3)")
    pb <- progress::progress_bar$new(
      format = "\r[:bar] :percent eta: :eta",
      clear = FALSE,
      total = nrow(bird_count_filenames) + 5,
      width = 100)
    pb$tick(0)
  }

  temp <- tempdir()
  full_path <- sbtools::item_file_download(sb_id = sb_conn,
                                           names = count_zip,
                                           destinations = file.path(temp, count_zip))
  tick(pb, quiet)

  unz_path <- utils::unzip(zipfile = full_path,
                           exdir = temp)
  tick(pb, quiet)

  bird <- vector(mode = "list", length = length(unz_path))
  for (i in 1:length(unz_path))
  {
    bird[[i]] <- utils::read.csv(utils::unzip(zipfile = unz_path[i],
                                              exdir = temp),
                                 stringsAsFactors = FALSE)
    tick(pb, quiet)
  }
  unlink(temp)

  # Coding around mistakes: 2020 data has countrynum and CountryNum
  #    in the 10th data frame of bird, so get rid of countrynum.
  #    Only relevant for level = "stop", this will probably be taken out
  #    next year lol
  #if (level == "stop") # issue appears to be fixed; throws an error with do.call(rbind) below.
  #{
  #  bird[[10]] <- bird[[10]][-c(2)]
  #}


  # The "StateNum" column is inconsistently named - fix it to be consistent
  bird <- lapply(bird, function(x){
    names(x) <- ifelse(names(x) == "statenum", "StateNum", names(x))
    x
  })
  tick(pb, quiet)


  bird <- do.call(rbind, bird)
  tick(pb, quiet)

  # column case conventions differ for state vs. stop level data, so we set:
  to_lower <- c('countrynum', 'statenum')
  to_upper <- 'Year'
  names(bird)[match(to_lower, tolower(names(bird)))] <- to_lower
  names(bird)[match(to_upper, tools::toTitleCase(names(bird)))] <- to_upper
  tick(pb, quiet)
  return(bird)

}

get_sb_id <- function(rel_date)
{
  if(rel_date == 2022){
    id_strng <- "625f151ed34e85fa62b7f926"
  }else{
    id_strng <- "5ea04e9a82cefae35a129d65"
  }
  return(id_strng)

}

tick <- function(pb, quiet) {
  if (!isTRUE(quiet)){
    pb$tick()
  }
}


#' Fetch Breeding Bird Survey dataset (TIDY)
#'
#' Use File Transfer Protocol (FTP) to fetch Breeding Bird Survey data from the
#' United States Geological Survey (USGS) FTP site. This is the raw data that is
#' uploaded to the site before any analyses are performed. A package-specific
#' directory is created on the user's computer (see documentation of
#' `rappdirs::appdir` for details of where this directory lives), and the BBS
#' data is saved to that directory for use by other functions. Before
#' downloading any data, the user must thoroughly read through the terms and
#' conditions of the user of the data and type the word "yes" to agree.
#'
#' @param force Logical. Should pre-exising BBS data be overwritten? Defaults to
#'   FALSE
#' @param compression Character. What compression should be used to save data?
#'   Defaults to `none` which takes up the most space but is the fastest to
#'   load. Must be one of `none`, `gz`, `bz2`, or `xz` (passed to
#'   `readr::write_rds()`'s `compress` argument).
#'
#'
#' @inheritParams common_docs
#'
#' @details BBS `state` level counts provide counts beginning in 1966,
#'   aggregated in five bins, each of which contains cumulative counts from 10
#'   of the 50 stops along a route. In contrats BBS `stop` level counts provides
#'   stop-level data beginning in 1997, which includes counts for each stop
#'   along routes individually. Note that stop-level data is not currently
#'   supported by the modelling utilities in bbsBayes.
#'
#' @examplesIf interactive()
#'
#' fetch_bbs_data(force = TRUE)
#' fetch_bbs_data(level = "stop", force = TRUE)
#' fetch_bbs_data(release = 2020, force = TRUE)
#' fetch_bbs_data(release = 2020, level = "stop", force = TRUE)
#'
#' @export
#'
fetch_bbs_data <- function(level = "state",
                           release = 2022,
                           force = FALSE,
                           quiet = FALSE,
                           compression = "none") {

  check_in(level, c("state", "stop"))
  check_in(release, c(2020, 2022))

  check_logical(c(quiet, force))

  out_file <- check_bbs_data(level, release, force, quiet)

  # Print Terms of Use
  terms <- readChar(system.file(paste0("data-terms-",release),
                                package = "bbsBayes"),
                    file.info(system.file(paste0("data-terms-",release),
                                          package = "bbsBayes"))$size)

  message(terms)
  agree <- readline(prompt = "Type \"yes\" (without quotes) to agree: ")
  if(agree != "yes") return(NULL)

  fetch_bbs_data_internal(level, release, force, quiet, out_file, compression)
}


fetch_bbs_data_internal <- function(level = "state", release = 2022,
                                    force = FALSE, quiet = TRUE,
                                    out_file = NULL, compression = "none") {

  if(is.null(out_file)) out_file <- check_bbs_data(level, release, force, quiet)

  if(!quiet) message("Connecting to USGS ScienceBase...", appendLF = FALSE)

  connection <- sbtools::item_get(sb_id = get_sb_id(rel_date = release))

  if(!is.null(connection) & !quiet) message("Connected!")

  # Download/load Data --------------
  birds <- get_birds(level, quiet, connection, force)
  routes <- get_routes(release, quiet, connection, force)
  weather <- get_weather(quiet, connection, force)
  regs <- readr::read_csv(
    system.file("data-import", "regs.csv", package = "bbsBayes"),
    col_types = "cnncc", progress = FALSE) %>%
    dplyr::rename_with(snakecase::to_snake_case) %>%
    dplyr::rename(country_num = "countrynum", state_num = "statenum")

  # Combine routes, weather, and region ----------------
  routes <- dplyr::inner_join(routes, weather,
                              by = c("country_num", "state_num", "route"))

  # remove off-road and water routes, as well as non-random and mini-routes
  routes <- routes %>%
    dplyr::filter(.data$route_type_detail_id == 1,
                  .data$route_type_id == 1,
                  .data$run_type == 1) %>%
    dplyr::select(-"stratum")

  routes <- dplyr::inner_join(routes, regs, by = c("country_num", "state_num"))

  # Combine routes and birds -----------
  unique_routes <- routes %>%
    dplyr::select("bcr", "state_num", "route", "country_num") %>%
    dplyr::distinct()

  birds <- dplyr::inner_join(birds, unique_routes,
                             by = c("state_num", "route", "country_num"))

  # Species Data ----------------

  if(!quiet) message("Downloading species data (Task 3/3)")

  temp <- tempfile()
  suppressMessages({
    full_path <- sbtools::item_file_download(sb_id = connection,
                                             names = "SpeciesList.txt",
                                             destinations = temp)
  })
  if(!quiet) message("\n") # For next message

  if(release == 2022) lskip <- 14 #silly differences in file structure
  if(release == 2020) lskip <- 11

  meta <- readr::read_lines(temp, n_max = 30, progress = FALSE)
  lskip <- stringr::str_which(meta, "---------")
  col_names <- stringr::str_split(meta[lskip - 1], "( )+") %>%
    unlist() %>%
    tolower() %>%
    stringr::str_remove("_common_name")
  col_names <- col_names[col_names != ""]

  # col_names should be:
  #  "seq", "aou", "english", "french", "spanish", "order",
  #  "family", "genus", "species"

  widths <- c(7, 6, 51, 51, 51, 51, 51, 51, NA)
  species <- readr::read_fwf(
    file = temp,
    col_positions = readr::fwf_widths(widths, col_names),
    col_types = "iiccccccc",
    skip = lskip, locale = readr::locale(encoding = "latin1"),
    progress = FALSE)


  # Combine species forms -------------------------------------
  b <- combine_species(birds, species, quiet)
  birds <- b$birds
  species <- b$species

  # Write Data -----------------------
  bbs_data <- list(birds = birds,
                   routes = routes,
                   species = species,
                   meta = data.frame(release = release,
                                     download_date = Sys.Date()))

  if(!quiet) message("Saving BBS data to ", out_file)
  readr::write_rds(bbs_data, file = out_file, compress = compression)

  # Clean Up -------------------------
  if(!quiet) message("Removing temp files")
  unlink(list.files(tempdir(), full.names = TRUE), recursive = TRUE)

}




bbs_dir <- function(quiet = TRUE) {
  d <- rappdirs::app_dir(appname = "bbsBayes")$data()

  if(!dir.exists(d)) {
    if(!quiet) message(paste0("Creating data directory at ", d))
    dir.create(d, recursive = TRUE)
  } else {
    if(!quiet) message(paste0("Using data directory at ", d))
  }

  d
}

#' Remove bbsBayes cache
#'
#' Remove all or some of the data downloaded via `fetch_bbs_data()` as well as
#' model executables created by `cmdstanr::cmdstan_model()` via `run_model()`.
#'
#' @param level Character. Data to remove, one of "all", "state", or "stop"
#' @param release Character/Numeric. Data to remove, one of "all", 2020, or 2022
#' @param cache_dir Logical. Remove entire cache directory (and all data
#'   contained therein)
#'
#' @return Nothing.
#'
#' @export
#'
#' @examples
#'
#' \dontrun{
#' # Remove everything
#' remove_cache(type = "all")
#'
#' # Remove all BBS data files (but not the dir)
#' remove_cache(level = "all", release = "all")
#'
#' # Remove all 'stop' data
#' remove_cache(level = "stop", release = "all")
#'
#' # Remove all 2020 data
#' remoremove_cacheve_bbs_data(level = "all", release = 2020)
#'
#' # Remove 2020 stop data
#' remove_cache(level = "stop", release = 2020)
#'
#' # Remove all model executables
#' remove_cache(type = "model")
#' }
#'
remove_cache <- function(type = "bbs_data", level, release) {
  if(type == "all") {
    message("Removing all data files (BBS data and Stan models) ",
            "and cache directory")
    unlink(bbs_dir(), recursive = TRUE)
  } else if(type == "bbs_data") {
    check_in(level, c("all", "state", "stop"))
    check_in(release, c("all", 2020, 2022))

    if(level == "all") level <- c("state", "stop")
    if(release == "all") release <- c("2020", "2022")

    f <- file.path(bbs_dir(), paste0("bbs_", level, "_data_", release, ".rds"))
    f <- f[file.exists(f)]
  } else if(type == "models") {
    f <- list.files(bbs_dir(), "CV$", full.names = TRUE)
  }

  if(length(f) > 0) {
    message("Removing ", paste0(f, collapse = ", "), " from the cache")
    unlink(f)
  } else message("No data files to remove")
}

#' Check whether BBS data exists
#'
#' @inheritParams common_docs
#'
#' @returns `TRUE` if the data is found, `FALSE` otherwise
#'
#' @export
have_bbs_data <- function(level = "state", release = 2022){
  check_in(level, c("all", "state", "stop"))
  check_in(release, c("all", 2020, 2022))

  if(level == "all") level <- c("state", "stop")
  if(release == "all") release <- c("2020", "2022")

  f <- file.path(bbs_dir(), paste0("bbs_", level, "_data_", release, ".rds"))

  file.exists(f)
}

get_encoding <- function() {
  if(l10n_info()[["UTF-8"]]) e <- "latin1" else e <- ""
  e
}

get_birds <- function(level, quiet, connection, force) {
  if (level == "state") count_zip <- "States.zip"
  if (level == "stop") count_zip <- "50-StopData.zip"

  bird_count_filenames <- system.file("data-import",
                                 paste0(level, "-dir.csv"),
                                 package = "bbsBayes") %>%
    utils::read.csv()

  if(!quiet) message("Downloading count data (Task 1/3)")
  suppressMessages({
    full_path <- sbtools::item_file_download(
      sb_id = connection,
      names = count_zip,
      destinations = file.path(tempdir(), count_zip),
      overwrite_file = force)})

  unz_path <- utils::unzip(zipfile = full_path, exdir = tempdir())

  birds <- unz_path %>%
    purrr::map(utils::unzip, exdir = tempdir()) %>%
    purrr::map(readr::read_csv, col_types = "nnnnnnnnnnnnnnn",
               progress = FALSE) %>%
    purrr::map(~dplyr::rename_with(.x, snakecase::to_snake_case)) %>%
    dplyr::bind_rows()

  unlink(full_path)

  birds
}

get_routes <- function(release, quiet, connection, force) {

  if (!quiet) {
    message("Downloading route data (Task 2/3)")
    message("  - routes...")
  }

  if(release == 2020) {
    # if necessary because file name changed between 2020 and 2022 releases
    rtsfl <- "routes.zip"
  } else{
    rtsfl <- "Routes.zip"
  }

  suppressMessages({
    full_path <- sbtools::item_file_download(
      sb_id = connection,
      names = rtsfl,
      destinations = file.path(tempdir(), rtsfl),
      overwrite_file = force)
  })

  routes <- readr::read_csv(
    utils::unzip(zipfile = full_path, exdir = tempdir()),
    na = c("NA", "", "NULL"),
    col_types = "nnncnnnnnnn", progress = FALSE,
    locale = readr::locale(encoding = "latin1")) %>%
    dplyr::rename_with(snakecase::to_snake_case)

  unlink(full_path)

  routes
}


get_weather <- function(quiet, connection, force) {

  if(!quiet) message("  - weather...")
  suppressMessages({
    full_path <- sbtools::item_file_download(
      sb_id = connection,
      names = "Weather.zip",
      destinations = file.path(tempdir(), "Weather.zip"),
      overwrite_file = force)
  })

  weather <- readr::read_csv(
    utils::unzip(zipfile = full_path, exdir = tempdir()),
    col_types = "nnnnnnnnnnnncnnnnnn",
    na = c("NA", "", "NULL"), progress = FALSE) %>%
    dplyr::rename_with(snakecase::to_snake_case)

  unlink(full_path)

  weather
}

combine_species <- function(birds, species, quiet = FALSE) {

  if(!quiet) message("Combining species forms for optional use")

  # Species list - Rename unidentified to name of combo group
  s <- species %>%
    dplyr::left_join(bbsBayes::species_forms, by = c("aou" = "aou_unid")) %>%
    dplyr::mutate(
      english = dplyr::if_else(
        !is.na(.data$english_combined), .data$english_combined, .data$english),
      french = dplyr::if_else(
        !is.na(.data$french_combined), .data$french_combined, .data$french)) %>%
    dplyr::select(names(species)) %>%
    dplyr::distinct() %>%
    dplyr::mutate(unid_combined = TRUE)

  # Birds - Pull out original, non-combined, non-unidentified species, and combine
  sp_forms <- tidyr::unnest(bbsBayes::species_forms, "aou_id")

  b <- birds %>%
    dplyr::inner_join(dplyr::select(sp_forms, "aou_unid", "aou_id"),
                      by = c("aou" = "aou_id")) %>%
    dplyr::mutate(aou = .data$aou_unid) %>%
    dplyr::select(-"aou_unid") %>%
    dplyr::mutate(unid_combined = TRUE)

  # Add combined species to both data sets
  # (note that this duplicates observations/listings, but permits use of
  # different species groupings when specifing later steps

  birds <- dplyr::mutate(birds, unid_combined = FALSE) %>%
    dplyr::bind_rows(b)

  species <- dplyr::mutate(species, unid_combined = FALSE) %>%
    dplyr::bind_rows(s)

  list("birds" = birds,
       "species" = species)
}
