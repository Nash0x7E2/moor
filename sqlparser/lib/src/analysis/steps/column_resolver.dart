part of '../analysis.dart';

class ColumnResolver extends RecursiveVisitor<void> {
  final AnalysisContext context;

  ColumnResolver(this.context);

  @override
  void visitSelectStatement(SelectStatement e) {
    _resolveSelect(e, []);
  }

  void _handle(Queryable queryable, List<Column> availableColumns) {
    queryable.when(
      isTable: (table) {
        _resolveTableReference(table);
        availableColumns.addAll(table.resultSet.resolvedColumns);
      },
      isSelect: (select) {
        // the inner select statement doesn't have access to columns defined in
        // the outer statements.
        _resolveSelect(select.statement, []);
        availableColumns.addAll(select.statement.resolvedColumns);
      },
      isJoin: (join) {
        for (var query in join.joins.map((j) => j.query)) {
          _handle(query, availableColumns);
        }
      },
    );
  }

  void _resolveSelect(SelectStatement s, List<Column> availableColumns) {
    final availableColumns = <Column>[];
    for (var queryable in s.from) {
      _handle(queryable, availableColumns);
    }

    final usedColumns = <Column>[];
    final scope = s.scope;

    // a select statement can include everything from its sub queries as a
    // result, but also expressions that appear as result columns
    for (var resultColumn in s.columns) {
      if (resultColumn is StarResultColumn) {
        if (resultColumn.tableName != null) {
          final tableResolver = scope
              .resolve<ResolvesToResultSet>(resultColumn.tableName, orElse: () {
            context.reportError(AnalysisError(
              type: AnalysisErrorType.referencedUnknownTable,
              message: 'Unknown table: ${resultColumn.tableName}',
              relevantNode: resultColumn,
            ));
          });
          usedColumns.addAll(tableResolver.resultSet.resolvedColumns);
        } else {
          // we have a * column, that would be all available columns
          usedColumns.addAll(availableColumns);
        }
      } else if (resultColumn is ExpressionResultColumn) {
        final name = _nameOfResultColumn(resultColumn);
        usedColumns.add(
          ExpressionColumn(name: name, expression: resultColumn.expression),
        );
      }
    }

    s.resolvedColumns = usedColumns;
  }

  String _nameOfResultColumn(ExpressionResultColumn c) {
    if (c.as != null) return c.as;

    if (c.expression is Reference) {
      return (c.expression as Reference).columnName;
    }

    // todo I think in this case it's just the literal lexeme?
    return 'TODO';
  }

  void _resolveTableReference(TableReference r) {
    final scope = r.scope;
    final resolvedTable = scope.resolve<Table>(r.tableName, orElse: () {
      context.reportError(AnalysisError(
        type: AnalysisErrorType.referencedUnknownTable,
        relevantNode: r,
        message: 'The table ${r.tableName} could not be found',
      ));
    });
    r.resolved = resolvedTable;
  }
}
