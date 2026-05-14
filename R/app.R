#' Launch the ttrssR Shiny dashboard  #contrib-balance-g-207
#'  #contrib-balance-g-208
#' @param host Host to listen on (default \code{"0.0.0.0"} for Docker).  #contrib-balance-g-209
#' @param port Port (default \code{3838}).  #contrib-balance-g-210
#' @param launch.browser Open a browser automatically.  #contrib-balance-g-211
#' @param ... Additional arguments passed to \code{shiny::runApp()}.  #contrib-balance-g-212
#' @export  #contrib-balance-g-213
run_dashboard <- function(host           = "0.0.0.0",  #contrib-balance-g-214
                          port           = 3838L,  #contrib-balance-g-215
                          launch.browser = interactive(),  #contrib-balance-g-216
                          ...) {  #contrib-balance-g-217
  app_dir <- system.file("shiny", package = "ttrssR")  #contrib-balance-g-218
  if (!nzchar(app_dir)) {  #contrib-balance-g-219
    cli::cli_abort("Shiny app not found. Is the package installed?")  #contrib-balance-g-220
  }  #contrib-balance-g-221
  shiny::runApp(app_dir, host = host, port = port,  #contrib-balance-g-222
                launch.browser = launch.browser, ...)  #contrib-balance-g-223
}  #contrib-balance-g-224
  #contrib-balance-g-225
#' Launch the MCP server (plumber)  #contrib-balance-g-226
#'  #contrib-balance-g-227
#' @param host Host to listen on.  #contrib-balance-g-228
#' @param port Port (default \code{8000}).  #contrib-balance-g-229
#' @param ... Additional arguments passed to \code{plumber::pr_run()}.  #contrib-balance-g-230
#' @export  #contrib-balance-g-231
run_mcp_server <- function(host = "0.0.0.0", port = 8000L, ...) {  #contrib-balance-g-232
  mcp_file <- system.file("mcp", "server.R", package = "ttrssR")  #contrib-balance-g-233
  if (!nzchar(mcp_file)) {  #contrib-balance-g-234
    cli::cli_abort("MCP server file not found. Is the package installed?")  #contrib-balance-g-235
  }  #contrib-balance-g-236
  pr <- plumber::plumb(mcp_file)  #contrib-balance-g-237
  plumber::pr_run(pr, host = host, port = port, ...)  #contrib-balance-g-238
}  #contrib-balance-g-239
