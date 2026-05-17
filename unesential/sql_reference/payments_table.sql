-- Create the payments table for financial tracking

CREATE TABLE payments (
    payment_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(order_id),
    amount NUMERIC(12,2) NOT NULL,
    type TEXT CHECK (type IN ('dp', 'pelunasan', 'buyback', 'custom')) NOT NULL,
    status TEXT CHECK (status IN ('pending', 'paid', 'cancelled')) DEFAULT 'pending',
    proof_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
