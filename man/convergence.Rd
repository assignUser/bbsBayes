% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/convergence.R
\name{convergence}
\alias{convergence}
\title{Convergence metrics}
\usage{
convergence(model_output)
}
\arguments{
\item{model_output}{List. Output of \code{run_model()}.}
}
\value{
Data frame of convergence metrics
}
\description{
Convergence metrics
}
\examples{

\donttest{
# Toy example with Pacific Wren sample data
# First, stratify the sample data
s <- stratify(by = "bbs_cws", sample_data = TRUE)

# Prepare the stratified data for use in modelling
d <- prepare_data(s, min_year = 2009, max_year = 2018)

# Now run the model (fast but not good, just for illustration)
m <- run_model(d, model = "first_diff",
               iter_sampling = 20, iter_warmup = 20, chains = 2)

# Calculate convergence metrics on each variable
conv <- convergence(m)
}

}
