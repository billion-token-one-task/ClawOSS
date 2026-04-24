export function preferAccurateMetrics<T extends { channel: string | null }>(
  rows: T[]
): T[] {
  const jsonlRows = rows.filter((row) => (row.channel || "").startsWith("jsonl:"));
  if (jsonlRows.length > 0) return jsonlRows;

  const nonEstimateRows = rows.filter(
    (row) => !["agent", "agent_estimate"].includes(row.channel || "")
  );
  return nonEstimateRows.length > 0 ? nonEstimateRows : rows;
}
