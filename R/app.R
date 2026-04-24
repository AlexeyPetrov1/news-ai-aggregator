#' Launch the ttrssR Shiny dashboard
#'
#' @param host Host to listen on (default \code{"0.0.0.0"} for Docker).
#' @param port Port (default \code{3838}).
#' @param launch.browser Open a browser automatically.
#' @param ... Additional arguments passed to \code{shiny::runApp()}.
#' @export
run_dashboard <- function(host           = "0.0.0.0",
                          port           = 3838L,
                          launch.browser = interactive(),
                          ...) {
  app_dir <- system.file("shiny", package = "ttrssR")
  if (!nzchar(app_dir)) {
    cli::cli_abort("Shiny app not found. Is the package installed?")
  }
  shiny::runApp(app_dir, host = host, port = port,
                launch.browser = launch.browser, ...)
}

#' Launch the MCP server (plumber)
#'
#' @param host Host to listen on.
#' @param port Port (default \code{8000}).
#' @param ... Additional arguments passed to \code{plumber::pr_run()}.
#' @export
run_mcp_server <- function(host = "0.0.0.0", port = 8000L, ...) {
  mcp_file <- system.file("mcp", "server.R", package = "ttrssR")
  if (!nzchar(mcp_file)) {
    cli::cli_abort("MCP server file not found. Is the package installed?")
  }
  pr <- plumber::plumb(mcp_file)
  plumber::pr_run(pr, host = host, port = port, ...)
}
