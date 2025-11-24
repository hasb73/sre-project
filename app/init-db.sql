-- Database initialization script for microservices
-- Creates tables required by all three services

-- Users table (used by frontend-api and business-logic)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Orders table (used by business-logic)
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    amount DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Ingested data table (used by data-ingest)
CREATE TABLE IF NOT EXISTS ingested_data (
    id SERIAL PRIMARY KEY,
    record_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    source VARCHAR(50) NOT NULL,
    region VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_ingested_data_type ON ingested_data(record_type);
CREATE INDEX IF NOT EXISTS idx_ingested_data_region ON ingested_data(region);
CREATE INDEX IF NOT EXISTS idx_ingested_data_created_at ON ingested_data(created_at);

-- Insert sample data for testing
INSERT INTO users (username, email) VALUES
    ('admin', 'admin@example.com'),
    ('testuser', 'test@example.com')
ON CONFLICT (username) DO NOTHING;

-- Grant permissions (adjust as needed)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO appuser;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO appuser;
