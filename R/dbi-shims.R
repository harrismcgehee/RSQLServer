#' @importFrom dplyr db_list_tables
#' @export
db_list_tables.SQLServerConnection <- function (con) {
  dbListTables(con)
}

#' @importFrom dplyr db_has_table
#' @export
db_has_table.SQLServerConnection <- function (con, table) {
  # Like method for MySQL, RSQLServer has no way to list temporary tables, so we
  # always NA to skip any local checks and rely on the database to throw
  # informative errors
  # See: https://github.com/imanuelcostigan/RSQLServer/issues/29
  NA
}

#' @importFrom dplyr db_save_query sql_subquery
#' @export
db_save_query.SQLServerConnection <- function (con, sql, name, temporary = TRUE,
  ...) {
  # http://smallbusiness.chron.com/create-table-query-results-microsoft-sql-50836.html
  if (temporary) name <- paste0("#", name)
  qry <- build_sql("SELECT * INTO ", ident(name), " FROM ",
    sql_subquery(con, sql), con = con)
  dbExecute(con, qry)
  name
}

#' @importFrom dplyr db_create_table escape ident sql_vector build_sql
#' @export

db_create_table.SQLServerConnection <- function(con, table, types,
  temporary = FALSE, ...) {
  assertthat::assert_that(assertthat::is.string(table), is.character(types))
  sql <- sqlCreateTable(con, table, types, temporary = temporary)
  dbExecute(con, sql)
  # Needs to return table name as temp tables are prefixed by `#` in SQL Server
  if (temporary) prefix <- "#" else prefix <- ""
  paste0(prefix, table)
}

#' @importFrom dplyr db_insert_into
#' @export

db_insert_into.SQLServerConnection <- function(con, table, values, temporary, ...) {
  # Temp tables cannot be appended to in SQL Server as their existence cannot
  # be checked by the API.
  if (temporary) {
    append <- FALSE
    overwrite <- TRUE
  } else {
    append <- TRUE
    overwrite <- FALSE
  }
  dbWriteTable(con, table, values, overwrite = overwrite, append = append)
}

#' @importFrom dplyr db_drop_table
#' @export

db_drop_table.SQLServerConnection <- function(con, table, force = FALSE, ...) {
  # IF EXISTS only supported by SQL Server 2016 (v. 13) and above.
  qry <- paste0("DROP TABLE ",
    if (force && dbGetInfo(con)$db.version > 12) "IF EXISTS ",
    dbQuoteIdentifier(con, table))
  assertthat::is.number(dbExecute(con, qry))
}

#' @importFrom dplyr db_create_index
#' @export
db_create_index.SQLServerConnection <- function(con, table, columns,
  name = NULL, unique = FALSE, ...) {
  # Modified from:
  # https://github.com/hadley/dplyr/blob/053a996cb12aeb8c0ac305cbe268c5590a4ea3e5/R/dbi-s3.r#L151
  # Work around: https://github.com/hadley/dplyr/issues/1912
  # SQL Server index creation does not return result set so dbGetQuery fails.
  assertthat::assert_that(assertthat::is.string(table), is.character(columns))
  name <- name %||% paste0(c(table, columns), collapse = "_")
  fields <- escape(ident(columns), parens = TRUE, con = con)
  sql <- build_sql(
    "CREATE ", if (unique) sql("UNIQUE "), "INDEX ", ident(name),
    " ON ", ident(table), " ", fields,
    con = con)
  assertthat::is.number(dbExecute(con, sql))
}

#' @importFrom dplyr db_analyze ident build_sql
#' @export
db_analyze.SQLServerConnection <- function (con, table, ...) {
  TRUE
}

# Inherited db_create_index.DBIConnection method from dplyr

#' @importFrom dplyr db_explain
#' @export
db_explain.SQLServerConnection <- function (con, sql, ...) {
  # SET SHOWPLAN_ALL available from SQL Server 2000 on.
  # https://technet.microsoft.com/en-us/library/aa259203(v=sql.80).aspx
  # http://msdn.microsoft.com/en-us/library/ms187735.aspx
  # http://stackoverflow.com/a/7359705/1193481
  dbSendStatement(con, "SET SHOWPLAN_ALL ON")
  on.exit(dbSendStatement(con, "SET SHOWPLAN_ALL OFF"))
  res <- dbGetQuery(con, sql) %>%
    dplyr::select_("StmtId", "NodeId", "Parent", "PhysicalOp", "LogicalOp",
      "Argument", "TotalSubtreeCost")
  paste(utils::capture.output(print(res)), collapse = "\n")
}
