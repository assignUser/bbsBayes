
# bbsBayes <img src="man/figures/logo.png" align="right"/>

[![CRAN_Status_Badge](http://www.r-pkg.org/badges/version/bbsBayes)](https://cran.r-project.org/package=bbsBayes)

This README file provides an overview of the functionality that can be
accomplished with ‘bbsBayes’. It is intended to provide enough
information for users to perform, at the very least, replications of
status and trend estimates from the Canadian Wildlife Service and/or
United States Geological Survey. However, it provides more in-depth and
advanced examples for subsetting data, custom regional summaries, and
more.

Additional resources: \* [Introductory bbsBayes
Workshop](https://github.com/AdamCSmithCWS/bbsBayes_Intro_Workshop) \*
[Journal Article with worked example](https://doi.org/10.5334/jors.329)

## Overview

bbsBayes is a package to perform hierarchical Bayesian analysis of North
American Breeding Bird Survey (BBS) data. ‘bbsBayes’ will run a full
model analysis for one or more species that you choose, or you can take
more control and specify how the data should be stratified, prepared for
Stan, or modelled.

<img src="man/figures/BARS_Continental_Trajectory.png"/>
<img src="man/figures/BARS_trendmap.png"/>

## Installation

Option 1: Stable release from CRAN

``` r
# To install from CRAN:
install.packages("bbsBayes")
```

Option 2: Less-stable development version

``` r
# To install the development version from GitHub:
install.packages("devtools")
library(devtools)
devtools::install_github("BrandonEdwards/bbsBayes")
```
