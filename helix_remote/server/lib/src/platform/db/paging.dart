/// The largest uuid, as a SQL expression: the cursor of the first page.
///
/// A page "after the cursor, newest first" is `WHERE id < COALESCE(@cursor,
/// the largest uuid) ORDER BY id DESC LIMIT n`: one plain range on the key,
/// which an index can walk backwards and stop at `n` rows. The usual
/// `(@cursor IS NULL OR id < @cursor)` is an `OR` the planner cannot turn into
/// a range once the statement has a generic plan (AUD-7-3).
const lastUuidSql = "'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid";
