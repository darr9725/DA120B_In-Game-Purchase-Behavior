Create TABLE raw_data (
	userID								UUID,
	age									NUMERIC,
	gender								VARCHAR(10),
	country								VARCHAR(50),
	device								VARCHAR(10),
	game_genre							VARCHAR(50),
	session_count						INT,
	average_session_length				REAL,
	spending_segment 					VARCHAR(20),
	in_app_purchase_amount				NUMERIC(10, 2),
	first_purchase_days_after_install	INT,
	payment_method						VARCHAR(50),
	last_purchase_date					DATE
)


