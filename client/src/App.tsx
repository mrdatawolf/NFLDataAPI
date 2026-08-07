import { useEffect, useState } from 'react';

type SourceInfo = {
  name: string;
  type: string;
  path: string | null;
  configured: boolean;
  available: boolean;
  last_run: { finished_at: string; status: string; rows_inserted: number } | null;
};

type Summary = {
  total_rows: number;
  total_tables: number;
  by_source: Record<string, { tables: number; rows: number }>;
};

type BronzeTable = { table_name: string; row_count: number };

type BronzeRow = {
  id: number;
  payload: Record<string, unknown>;
  batch_id: string;
  ingested_at: string;
};

export default function App() {
  const [sources, setSources] = useState<SourceInfo[]>([]);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [tables, setTables] = useState<BronzeTable[]>([]);
  const [selectedTable, setSelectedTable] = useState('');
  const [rows, setRows] = useState<BronzeRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [scanning, setScanning] = useState(false);

  const loadData = async () => {
    setLoading(true);
    try {
      const [sourcesResponse, summaryResponse, tablesResponse] = await Promise.all([
        fetch('/api/sources'),
        fetch('/api/summary'),
        fetch('/api/bronze/tables')
      ]);
      const sourcesData = await sourcesResponse.json();
      const summaryData = await summaryResponse.json();
      const tablesData = await tablesResponse.json();
      setSources(sourcesData.sources || []);
      setSummary(summaryData);
      setTables(tablesData.tables || []);
    } finally {
      setLoading(false);
    }
  };

  const loadRows = async (tableName: string) => {
    setSelectedTable(tableName);
    if (!tableName) {
      setRows([]);
      return;
    }
    const [source, ...rest] = tableName.split('__');
    const response = await fetch(`/api/bronze/${source}/${rest.join('__')}?limit=50`);
    const data = await response.json();
    setRows(data.rows || []);
  };

  useEffect(() => {
    loadData();
  }, []);

  const triggerScan = async () => {
    setScanning(true);
    try {
      const response = await fetch('/api/ingest/scan', { method: 'POST' });
      const data = await response.json();
      alert(JSON.stringify(data, null, 2));
      await loadData();
      if (selectedTable) await loadRows(selectedTable);
    } finally {
      setScanning(false);
    }
  };

  const payloadColumns = rows.length > 0 ? Object.keys(rows[0].payload) : [];

  return (
    <div style={{ padding: 24, fontFamily: 'sans-serif' }}>
      <h1>NFL Data API</h1>
      <p>Unified mill data — Raptor, Saw Filers, and Porter landed into a bronze layer in PGlite.</p>

      <div style={{ display: 'flex', gap: 12, marginBottom: 16, flexWrap: 'wrap', alignItems: 'center' }}>
        <button onClick={triggerScan} disabled={scanning}>{scanning ? 'Scanning…' : 'Run scan'}</button>
        <button onClick={loadData} disabled={loading}>Refresh</button>
        <a href="/api/docs" target="_blank" rel="noreferrer">API docs</a>
        {summary && (
          <span>
            <strong>Total bronze rows:</strong> {summary.total_rows.toLocaleString()} across {summary.total_tables} tables
          </span>
        )}
      </div>

      <h2>Sources</h2>
      <table style={{ borderCollapse: 'collapse', marginBottom: 24 }}>
        <thead>
          <tr>
            {['Source', 'Type', 'Status', 'Bronze tables', 'Bronze rows', 'Last run'].map((header) => (
              <th key={header} style={{ borderBottom: '1px solid #ccc', textAlign: 'left', padding: '4px 12px 4px 0' }}>{header}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {sources.map((source) => (
            <tr key={source.name}>
              <td style={{ padding: '4px 12px 4px 0' }}>{source.name}</td>
              <td style={{ padding: '4px 12px 4px 0' }}>{source.type}</td>
              <td style={{ padding: '4px 12px 4px 0' }}>
                {!source.configured ? 'not configured' : source.available ? 'available' : 'path missing'}
              </td>
              <td style={{ padding: '4px 12px 4px 0' }}>{summary?.by_source[source.name]?.tables ?? 0}</td>
              <td style={{ padding: '4px 12px 4px 0' }}>{(summary?.by_source[source.name]?.rows ?? 0).toLocaleString()}</td>
              <td style={{ padding: '4px 12px 4px 0' }}>
                {source.last_run ? `${source.last_run.status} @ ${new Date(source.last_run.finished_at).toLocaleString()}` : '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <h2>Bronze browser</h2>
      <div style={{ marginBottom: 12 }}>
        <select value={selectedTable} onChange={(event) => loadRows(event.target.value)}>
          <option value="">Select a bronze table…</option>
          {tables.map((table) => (
            <option key={table.table_name} value={table.table_name}>
              {table.table_name} ({table.row_count.toLocaleString()} rows)
            </option>
          ))}
        </select>
      </div>

      {rows.length > 0 && (
        <div style={{ overflowX: 'auto' }}>
          <table style={{ borderCollapse: 'collapse', fontSize: 13 }}>
            <thead>
              <tr>
                <th style={{ borderBottom: '1px solid #ccc', textAlign: 'left', padding: '4px 12px 4px 0' }}>ingested_at</th>
                {payloadColumns.map((column) => (
                  <th key={column} style={{ borderBottom: '1px solid #ccc', textAlign: 'left', padding: '4px 12px 4px 0' }}>{column}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id}>
                  <td style={{ padding: '4px 12px 4px 0', whiteSpace: 'nowrap' }}>{new Date(row.ingested_at).toLocaleString()}</td>
                  {payloadColumns.map((column) => (
                    <td key={column} style={{ padding: '4px 12px 4px 0' }}>{String(row.payload[column] ?? '')}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
