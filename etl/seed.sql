CREATE OR REPLACE FUNCTION seed_users(p_count INTEGER DEFAULT 100)
RETURNS VOID AS $$
BEGIN
  INSERT INTO users (first_name, last_name, email)
  SELECT
    'first_' || i,
    'last_' || i,
    'user_' || i || '_' || substr(md5(random()::text), 1, 6) || '@example.com'
  FROM generate_series(1, p_count) AS i;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION seed_trades(p_count INTEGER DEFAULT 1000)
RETURNS VOID AS $$
DECLARE
  v_user_ids INTEGER[];
  v_user_count INTEGER;
  v_symbols VARCHAR[] := ARRAY['BTC-USDT', 'ETH-USDT', 'SOL-USDT', 'BNB-USDT', 'XRP-USDT'];
  v_maker_id INTEGER;
  v_taker_id INTEGER;
  v_symbol VARCHAR;
  v_side VARCHAR;
  v_price NUMERIC(36, 18);
  v_quantity NUMERIC(36, 18);
BEGIN
  SELECT array_agg(id) INTO v_user_ids FROM users;
  v_user_count := array_length(v_user_ids, 1);

  IF v_user_count IS NULL OR v_user_count < 2 THEN
    RAISE EXCEPTION 'seed_trades requires at least 2 users, found %', COALESCE(v_user_count, 0);
  END IF;

  FOR i IN 1..p_count LOOP
    v_maker_id := v_user_ids[1 + floor(random() * v_user_count)];
    LOOP
      v_taker_id := v_user_ids[1 + floor(random() * v_user_count)];
      EXIT WHEN v_taker_id <> v_maker_id;
    END LOOP;

    v_symbol := v_symbols[1 + floor(random() * array_length(v_symbols, 1))];
    v_side := CASE WHEN random() < 0.5 THEN 'BUY' ELSE 'SELL' END;
    v_price := round((random() * 90000 + 100)::numeric, 8);
    v_quantity := round((random() * 10 + 0.0001)::numeric, 8);

    INSERT INTO trades (
      symbol, maker_order_id, taker_order_id, user_maker_id, user_taker_id,
      taker_side, price, quantity, quote_quantity, maker_fee, taker_fee, traded_at
    ) VALUES (
      v_symbol,
      i * 2 - 1,
      i * 2,
      v_maker_id,
      v_taker_id,
      v_side,
      v_price,
      v_quantity,
      v_price * v_quantity,
      v_price * v_quantity * 0.0004,
      v_price * v_quantity * 0.001,
      now() - (random() * interval '30 days')
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- SELECT seed_users(10);
-- SELECT seed_trades(100);

ALTER TABLE public.users ADD COLUMN phone VARCHAR(20);

ALTER TABLE public.users DROP COLUMN phone;
