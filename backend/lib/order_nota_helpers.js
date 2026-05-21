/**
 * Nomor nota order — fungsi DB `generate_nota_order` atau fallback JS.
 */

const ORDER_TYPE_CODES = {
  jual: 'JL',
  buyback: 'BB',
  service: 'SV',
  custom: 'CT',
};

async function resolveNotaOrder(client, { branch_id, order_type, order_number }) {
  const explicit = String(order_number ?? '').trim();
  if (explicit) return explicit;

  try {
    const r = await client.query(
      'SELECT generate_nota_order($1, $2) AS nota_order',
      [branch_id, order_type]
    );
    const v = r.rows[0]?.nota_order;
    if (v) return String(v);
  } catch (e) {
    if (e?.code !== '42883') {
      throw e;
    }
    // function does not exist — fallback below
  }

  const br = await client.query(
    'SELECT initials, code FROM branches WHERE branch_id = $1',
    [branch_id]
  );
  if (br.rows.length === 0) {
    throw new Error(`branch_id ${branch_id} tidak ditemukan`);
  }
  const { initials, code } = br.rows[0];
  const suffix = ORDER_TYPE_CODES[order_type];
  if (!suffix) {
    throw new Error(`Invalid order_type: ${order_type}`);
  }

  let seq = Date.now() % 100000000;
  try {
    const seqRes = await client.query(`SELECT nextval('order_nota_seq') AS n`);
    seq = parseInt(seqRes.rows[0]?.n, 10) || seq;
  } catch (_) {
    // sequence may not exist; timestamp fallback
  }

  const init = String(initials ?? '').trim() || 'XX';
  const brCode = String(code ?? '').trim() || 'BR';
  return `${init}-${brCode}-${suffix}-${String(seq).padStart(8, '0')}`;
}

module.exports = { resolveNotaOrder };
