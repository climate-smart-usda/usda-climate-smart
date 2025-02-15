library(magrittr)
library(tidyverse)
library(patchwork)
library(terra)

force.redo = FALSE

if(!file.exists(file.path("data-derived", "fsa-counties.parquet")) | force.redo){
  unlink(file.path("data-derived", "fsa-counties.parquet"))
  
  download.file("https://raw.githubusercontent.com/mt-climate-office/fsa-lfp-eligibility/main/fsa-counties/FSA_Counties_dd17.gdb.zip",
                destfile = file.path("data-raw", "FSA_Counties_dd17.gdb.zip"))
  
  gdalUtilities::ogr2ogr(src_datasource_name = "/vsizip/data-raw/FSA_Counties_dd17.gdb.zip",
                         dst_datasource_name = "data-derived/fsa-counties.parquet",
                         t_srs = "EPSG:4326",
                         config_options = c(COMPRESSION="BROTLI",
                                            GEOMETRY_ENCODING="GEOARROW",
                                            WRITE_COVERING_BBOX="NO"),
                         f = "PARQUET", 
                         nlt = "MULTIPOLYGON",
                         overwrite = TRUE
  )
  
  sf::read_sf(file.path("data-derived", "fsa-counties.parquet")) %>%
    dplyr::group_by(FSA_CODE = FSA_STCOU) %>%
    dplyr::summarise(.groups = "drop") %>%
    sf::st_make_valid() %>%
    sf::st_intersection(
      tigris::counties() %>%
        dplyr::summarise() %>%
        sf::st_transform(4326) %>%
        sf::st_make_valid()
    ) %>%
    sf::write_sf(file.path("data-derived", "fsa-counties.parquet"),
                 layer_options = c("COMPRESSION=BROTLI",
                                   "GEOMETRY_ENCODING=GEOARROW",
                                   "WRITE_COVERING_BBOX=NO"),
                 driver = "Parquet")
}

if(!file.exists(file.path("data-derived", "fsa-county-names.parquet"))) {
  sf::read_sf("/vsizip/data-raw/FSA_Counties_dd17.gdb.zip") %>% 
    dplyr::transmute(
      FSA_CODE = FSA_STCOU, 
      County = FSA_Name,
      State = STATENAME
    ) %>% 
    sf::st_drop_geometry() %>%
    dplyr::arrange(FSA_CODE) %>%
    dplyr::distinct() %>%
    arrow::write_parquet(file.path("data-derived", "fsa-county-names.parquet"),
                         version = "latest",
                         compression = "brotli")
}

if(!file.exists(file.path("data-derived", "fsa-counties.fgb")) | force.redo){
  unlink(file.path("data-derived", "fsa-counties.fgb"))
  
  download.file("https://raw.githubusercontent.com/mt-climate-office/fsa-lfp-eligibility/main/fsa-counties/FSA_Counties_dd17.gdb.zip",
                destfile = file.path("data-raw", "FSA_Counties_dd17.gdb.zip"))
  
  gdalUtilities::ogr2ogr(
    src_datasource_name = "/vsizip/data-raw/FSA_Counties_dd17.gdb.zip",
    dst_datasource_name = "data-derived/fsa-counties.fgb",
    t_srs = "EPSG:4326",
    config_options = c(
      COMPRESSION = "BROTLI",
      # GEOMETRY_ENCODING = "GEOARROW",
      WRITE_COVERING_BBOX = "NO"
    ),
    f = "FlatGeobuf",
    nlt = "MULTIPOLYGON",
    overwrite = TRUE
  )
  
  dat <- sf::read_sf(file.path("data-derived", "fsa-counties.fgb")) %>%
    dplyr::group_by(FSA_CODE = FSA_STCOU) %>%
    dplyr::summarise(.groups = "drop") %>%
    sf::st_make_valid() %>%
    sf::st_intersection(
      tigris::counties() %>%
        dplyr::summarise() %>%
        sf::st_transform(4326) %>%
        sf::st_make_valid()
    )
  
    sf::write_sf(dat, file.path("data-derived", "fsa-counties.fgb"), delete_dsn = TRUE)
}

fsa_counties <-
  sf::read_sf(file.path("data-derived", "fsa-counties.parquet"))


## USDM Drought Assessment through time
# if(!file.exists(file.path("data-derived", "usdm-counties.parquet")) | force.redo){
  unlink(file.path("data-derived", "usdm-counties.parquet"))
  
  # source("~/git/mt-climate-office/usdm-archive/usdm-archive.R", 
  #        local = TRUE, 
  #        chdir = TRUE)
  
  file.copy("~/git/mt-climate-office/usdm-archive/usdm.mp4", 
            "usdm.mp4",
            overwrite = TRUE)
  
  usdm <- sf::read_sf("../usdm-archive/parquet/")
  usdm_raster <- terra::rast(list.files("../usdm-archive/tif/", 
                                        pattern = "tif$", 
                                        full.names = TRUE))
  
  exactextractr::exact_extract(usdm_raster, 
                               sf::st_transform(fsa_counties, "EPSG:5070"), 
                               fun = "max", 
                               append_cols = TRUE) %>%
    tibble::as_tibble() %>%
    tidyr::pivot_longer(-FSA_CODE, 
                        names_to = "Date", 
                        values_to = "USDM Class") %>%
    dplyr::mutate(Date = stringr::str_remove(Date, "max.") %>%
                    lubridate::as_date(),
                  `USDM Class` = as.integer(`USDM Class`) %>%
                    factor(levels = levels(usdm_raster[[1]])[[1]][[1]],
                           labels = levels(usdm_raster[[1]])[[1]][[2]],
                           ordered = TRUE)) %>%
    dplyr::arrange(FSA_CODE, Date, `USDM Class`) %>%
    arrow::write_parquet(file.path("data-derived", "usdm-counties.parquet"),
                         version = "latest",
                         compression = "brotli")
# }

usdm_counties <-
  arrow::read_parquet(file.path("data-derived", "usdm-counties.parquet"))


## Normal Grazing Periods
if(!file.exists(file.path("data-derived", "fsa-normal-grazing-periods.parquet")) | force.redo){
  unlink(file.path("data-derived", "fsa-normal-grazing-periods.parquet"))
  
  readr::read_csv(
    "https://raw.githubusercontent.com/mt-climate-office/fsa-normal-grazing-period/main/fsa-normal-grazing-period.csv"
  ) %>%
    dplyr::group_by(dplyr::across(!`Type Name`)) %>%
    dplyr::summarise(`Type Name` = paste0(`Type Name`, collapse = "; ")) %>%
    dplyr::select(FSA_CODE, `Crop Name`, `Type Name`, `Grazing Period Start Date`, `Grazing Period End Date`) %>%
    arrow::write_parquet(file.path("data-derived", "fsa-normal-grazing-periods.parquet"),
                         version = "latest",
                         compression = "brotli")
}

fsa_normal_grazing_periods <-
  arrow::read_parquet(file.path("data-derived", "fsa-normal-grazing-periods.parquet"))

## NAP-190 normal grazing periods (based on ERA5)



## LFP Eligibility through time
if(!file.exists(file.path("data-derived", "fsa-lfp-eligibility.parquet")) | force.redo){
  unlink(file.path("data-derived", "fsa-lfp-eligibility.parquet"))
  
  readr::read_csv(
    "https://raw.github.com/mt-climate-office/fsa-lfp-eligibility/main/fsa-lfp-eligibility.csv"
  ) %>%
    dplyr::mutate(Payments = pmin(FACTOR, MONTHS, na.rm = TRUE)) %>%
    dplyr::select(FSA_CODE,
                  Year = PROGRAM_YEAR,
                  `Pasture Type` = PASTURE_TYPE,
                  Payments,
                  `Grazing Period Start Date` = GROWING_SEASON_START,
                  `Grazing Period End Date` = GROWING_SEASON_END) %>%
    dplyr::mutate(Year = as.integer(Year),
                  Payments = as.integer(Payments)) %>%
    dplyr::arrange(FSA_CODE, Year, `Pasture Type`) %>%
    arrow::write_parquet(file.path("data-derived", "fsa-lfp-eligibility.parquet"),
                         version = "latest",
                         compression = "brotli")
  
}

fsa_lfp_eligibility <-
  arrow::read_parquet(file.path("data-derived", "fsa-lfp-eligibility.parquet"))


## FSA Payments through time
if(!file.exists(file.path("data-derived", "fsa-farm-payments.parquet")) | force.redo){
  unlink(file.path("data-derived", "fsa-farm-payments.parquet"))
  
  list.files("data-raw/fsa-payment-files",
               full.names = TRUE) %>%
    purrr::map_dfr(readxl::read_excel) %>%
    dplyr::mutate(`State FSA Code` = stringr::str_pad(`State FSA Code`, width = 2, side = "left", pad = "0"),
                  `County FSA Code` = stringr::str_pad(`State FSA Code`, width = 3, side = "left", pad = "0"),
                  FSA_CODE = paste0(`State FSA Code`, `County FSA Code`)) %>%
    dplyr::select(!c(`Delivery Point Bar Code`, `State FSA Code`, `County FSA Code`)) %>%
    dplyr::select(FSA_CODE,
                  `Accounting Program Code`,
                  `Accounting Program Description`,
                  `Accounting Program Year`,
                  Name = `Formatted Payee Name`,
                  `Mail To` = `Address Information Line`,
                  Address = `Delivery Address Line`,
                  City = `City Name`,
                  ST = `State Abbreviation`,
                  Zip = `Zip Code`,
                  `Payment Date`,
                  `Payment Amount` = `Disbursement Amount`) %>%
    dplyr::group_by(across(c(-`Payment Amount`))) %>%
    dplyr::summarise(`Payment Amount` = sum(`Payment Amount`, na.rm = TRUE), .groups = "drop") %>%
    dplyr::arrange(FSA_CODE, `Accounting Program Year`, `Accounting Program Code`, City, ST, Name, Address) %>%
    dplyr::mutate(`Payment Date` = lubridate::as_date(`Payment Date`)) %>%
    arrow::write_parquet(file.path("data-derived", "fsa-farm-payments.parquet"),
                         version = "latest",
                         compression = "brotli")
  
}

fsa_farm_payments <-
  arrow::read_parquet(file.path("data-derived", "fsa-farm-payments.parquet"))
