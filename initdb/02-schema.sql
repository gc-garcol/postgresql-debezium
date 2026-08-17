CREATE TABLE customers (
  id SERIAL,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  PRIMARY KEY(id)
);

CREATE TABLE users (
  id SERIAL,
  first_name VARCHAR(64) NOT NULL,
  last_name VARCHAR(64) NOT NULL,
  email VARCHAR(128) NOT NULL,
  PRIMARY KEY(id)
);

CREATE TABLE trades (
  id SERIAL,
  symbol VARCHAR(32) NOT NULL,
  maker_order_id BIGINT NOT NULL,
  taker_order_id BIGINT NOT NULL,
  user_maker_id INTEGER NOT NULL,
  user_taker_id INTEGER NOT NULL,
  taker_side VARCHAR(4) NOT NULL CHECK (taker_side IN ('BUY', 'SELL')),
  price NUMERIC(36, 18) NOT NULL,
  quantity NUMERIC(36, 18) NOT NULL,
  quote_quantity NUMERIC(36, 18) NOT NULL,
  maker_fee NUMERIC(36, 18) NOT NULL DEFAULT 0,
  taker_fee NUMERIC(36, 18) NOT NULL DEFAULT 0,
  traded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(id),
  FOREIGN KEY (user_maker_id) REFERENCES users(id),
  FOREIGN KEY (user_taker_id) REFERENCES users(id)
);
