INSERT INTO agronizer.access_codes (code,purchased_at,expires_at,activated_at,activation_count,slug,user_id,payment_id, activation_count ) VALUES
	 ('654321',NOW(),NOW() + INTERVAL 6 MONTH,NOW(),1,'microgreens','user_id',NULL, 1);
