'use strict';

let _cachedPaymentsProofColumnExists = null; // boolean | null (unknown)
async function paymentsHasProofUrlColumn(client) {
  if (_cachedPaymentsProofColumnExists !== null) return _cachedPaymentsProofColumnExists;
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'payments'
          AND column_name = 'proof_url'
        LIMIT 1
      `,
      []
    );
    _cachedPaymentsProofColumnExists = r.rows.length > 0;
  } catch (_) {
    _cachedPaymentsProofColumnExists = false;
  }
  return _cachedPaymentsProofColumnExists;
}

let _cachedPaymentsValidatedByColumnExists = null; // boolean | null (unknown)
async function paymentsHasValidatedByColumn(client) {
  if (_cachedPaymentsValidatedByColumnExists !== null) {
    return _cachedPaymentsValidatedByColumnExists;
  }
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'payments'
          AND column_name = 'validated_by'
        LIMIT 1
      `,
      []
    );
    _cachedPaymentsValidatedByColumnExists = r.rows.length > 0;
  } catch (_) {
    _cachedPaymentsValidatedByColumnExists = false;
  }
  return _cachedPaymentsValidatedByColumnExists;
}

let _cachedOrdersPickedUpAtColumnExists = null; // boolean | null (unknown)
async function ordersHasPickedUpAtColumn(client) {
  if (_cachedOrdersPickedUpAtColumnExists !== null) {
    return _cachedOrdersPickedUpAtColumnExists;
  }
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'orders'
          AND column_name = 'picked_up_at'
        LIMIT 1
      `,
      []
    );
    _cachedOrdersPickedUpAtColumnExists = r.rows.length > 0;
  } catch (_) {
    _cachedOrdersPickedUpAtColumnExists = false;
  }
  return _cachedOrdersPickedUpAtColumnExists;
}

let _cachedPaymentsPaymentDateColumnExists = null;
async function paymentsHasPaymentDateColumn(client) {
  if (_cachedPaymentsPaymentDateColumnExists !== null) {
    return _cachedPaymentsPaymentDateColumnExists;
  }
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'payments'
          AND column_name = 'payment_date'
        LIMIT 1
      `,
      []
    );
    _cachedPaymentsPaymentDateColumnExists = r.rows.length > 0;
  } catch (_) {
    _cachedPaymentsPaymentDateColumnExists = false;
  }
  return _cachedPaymentsPaymentDateColumnExists;
}

let _cachedPaymentsRevenueBranchColumnExists = null;
async function paymentsHasRevenueBranchColumn(client) {
  if (_cachedPaymentsRevenueBranchColumnExists !== null) {
    return _cachedPaymentsRevenueBranchColumnExists;
  }
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'payments'
          AND column_name = 'revenue_branch_id'
        LIMIT 1
      `,
      []
    );
    _cachedPaymentsRevenueBranchColumnExists = r.rows.length > 0;
  } catch (_) {
    _cachedPaymentsRevenueBranchColumnExists = false;
  }
  return _cachedPaymentsRevenueBranchColumnExists;
}

module.exports = {
  paymentsHasProofUrlColumn,
  paymentsHasValidatedByColumn,
  paymentsHasPaymentDateColumn,
  ordersHasPickedUpAtColumn,
  paymentsHasRevenueBranchColumn,
};
