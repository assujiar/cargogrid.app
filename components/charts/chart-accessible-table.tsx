/**
 * Accessible data-table alternative every chart must offer (CargoGrid Chart System,
 * "do not rely solely on a canvas/SVG chart to communicate data"). Reuses the real
 * `DataTable` primitive directly -- not a second table implementation.
 */

import { DataTable, type DataTableColumn } from "../tables/data-table.tsx";

export interface ChartAccessibleTableProps<Row> {
  readonly caption: string;
  readonly columns: readonly DataTableColumn<Row>[];
  readonly rows: readonly Row[];
  readonly rowKey: (row: Row) => string;
}

export function ChartAccessibleTable<Row>({ caption, columns, rows, rowKey }: ChartAccessibleTableProps<Row>) {
  return <DataTable caption={caption} columns={columns} rows={rows} rowKey={rowKey} emptyMessage="No data." />;
}
