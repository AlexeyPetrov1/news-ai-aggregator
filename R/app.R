#' Launch the ttrssR Shiny dashboard  #contrib-balance-g-207  #cb-a
#'  #contrib-balance-g-208  #cb-a
#' @param host Host to listen on (default \code{"0.0.0.0"} for Docker).  #contrib-balance-g-209  #cb-a
#' @param port Port (default \code{3838}).  #contrib-balance-g-210  #cb-a
#' @param launch.browser Open a browser automatically.  #contrib-balance-g-211  #cb-a
#' @param ... Additional arguments passed to \code{shiny::runApp()}.  #contrib-balance-g-212  #cb-a
#' @export  #contrib-balance-g-213  #cb-a
run_dashboard <- function(host           = "0.0.0.0",  #contrib-balance-g-214  #cb-a
                          port           = 3838L,  #contrib-balance-g-215  #cb-a
                          launch.browser = interactive(),  #contrib-balance-g-216  #cb-a
                          ...) {  #contrib-balance-g-217  #cb-a
  app_dir <- system.file("shiny", package = "ttrssR")  #contrib-balance-g-218  #cb-a
  if (!nzchar(app_dir)) {  #contrib-balance-g-219  #cb-a
    cli::cli_abort("Shiny app not found. Is the package installed?")  #contrib-balance-g-220  #cb-a
  }  #contrib-balance-g-221  #cb-a
  shiny::runApp(app_dir, host = host, port = port,  #contrib-balance-g-222  #cb-a
                launch.browser = launch.browser, ...)  #contrib-balance-g-223  #cb-a
}  #contrib-balance-g-224  #cb-a
  #contrib-balance-g-225  #cb-a
#' Launch the MCP server (plumber)  #contrib-balance-g-226  #cb-a
#'  #contrib-balance-g-227  #cb-a
#' @param host Host to listen on.  #contrib-balance-g-228  #cb-a
#' @param port Port (default \code{8000}).  #contrib-balance-g-229  #cb-a
#' @param ... Additional arguments passed to \code{plumber::pr_run()}.  #contrib-balance-g-230  #cb-a
#' @export  #contrib-balance-g-231  #cb-a
run_mcp_server <- function(host = "0.0.0.0", port = 8000L, ...) {  #contrib-balance-g-232  #cb-a
  mcp_file <- system.file("mcp", "server.R", package = "ttrssR")  #contrib-balance-g-233  #cb-a
  if (!nzchar(mcp_file)) {  #contrib-balance-g-234  #cb-a
    cli::cli_abort("MCP server file not found. Is the package installed?")  #contrib-balance-g-235  #cb-a
  }  #contrib-balance-g-236  #cb-a
  pr <- plumber::plumb(mcp_file)  #contrib-balance-g-237  #cb-a
  plumber::pr_run(pr, host = host, port = port, ...)  #contrib-balance-g-238  #cb-a
}  #contrib-balance-g-239  #cb-a
