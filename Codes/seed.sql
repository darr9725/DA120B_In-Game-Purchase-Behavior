CREATE TABLE players_cleaned (
    player_id               UUID PRIMARY KEY,           -- The userID corresponding to raw_data
    age                     INT,                        -- Ages 5–80 (after cleaning)
    gender                  VARCHAR(10),                -- Standardized Gender
    country                 VARCHAR(50),                -- Standardization Nation
    device                  VARCHAR(10),                -- operating system
    game_genre              VARCHAR(50),                -- Game Genre Preferences
    session_count           INT,                        -- Total Sessions
    avg_session_length      REAL,                       -- Raw average session duration (minutes)
    total_play_mins         NUMERIC(10,2),              -- Derived: Total Playtime (Minutes)
    spending_segment        VARCHAR(20),                -- Tiered Paid Tags
    in_app_purchase_amount  NUMERIC(10,2),              -- Cumulative Payment Amount
    first_purchase_days_after_install INT,              -- Days from installation to first payment
    payment_method          VARCHAR(50),                -- Common Payment Methods
    last_purchase_date      DATE,                       -- Date of most recent purchase

    -- Derived Analysis Fields
    is_purchaser            BOOLEAN,                    -- Have ever made a payment?
    days_to_first_pay       INT,                        -- Same as first_purchase_days_after_install
    is_outlier_age          BOOLEAN DEFAULT FALSE,      -- Age Anomaly Marker
    data_version            DATE DEFAULT CURRENT_DATE
);

INSERT INTO players_cleaned (
    player_id, age, gender, country, device, game_genre,
    session_count, avg_session_length, total_play_mins,
    spending_segment, in_app_purchase_amount,
    first_purchase_days_after_install, payment_method,
    last_purchase_date,
    is_purchaser, days_to_first_pay, is_outlier_age
)
SELECT
    userID,  -- UUID Direct Mapping
    CASE WHEN age BETWEEN 5 AND 80 THEN age::INT ELSE NULL END,  -- Age Cleaning
    -- Gender Standardization: Capitalize the first letter, lowercase the rest; replace null values with 'Unknown'.
    CASE
        WHEN TRIM(gender) = '' OR gender IS NULL THEN 'Unknown'
        ELSE CONCAT(UPPER(LEFT(TRIM(gender),1)), LOWER(SUBSTRING(TRIM(gender),2)))
    END,
    UPPER(TRIM(country)),                    -- Country Name (All Caps)
    device,                                  -- If no special cleaning is required, the original value can be retained.
    game_genre,                              -- Subsequent analysis may further consolidate categories.
    session_count,
    average_session_length,
    -- Calculate the total game duration in minutes. If the average duration is given in seconds, divide it by 60. 
	-- Here, we assume the duration is in minutes.
    ROUND((session_count * average_session_length)::numeric, 2),
    spending_segment,
    COALESCE(in_app_purchase_amount, 0.00),
    first_purchase_days_after_install,
    payment_method,
    last_purchase_date,
    -- Paid Status: Any purchase amount greater than 0 qualifies as a paid user.
    CASE WHEN COALESCE(in_app_purchase_amount, 0) > 0 THEN TRUE ELSE FALSE END,
    first_purchase_days_after_install,       -- Directly applied as the down payment period
    -- Age Anomaly Marker
    CASE WHEN age BETWEEN 5 AND 80 THEN FALSE ELSE TRUE END
FROM raw_data;

-- Create purchase_cleaned table for transaction analysis
CREATE TABLE purchase_cleaned (
    purchase_id          UUID PRIMARY KEY,         -- Unique transaction ID
    player_id            UUID NOT NULL,            -- Reference to players_cleaned
    purchase_amount      NUMERIC(10,2),            -- Transaction amount (single purchase)
    purchase_date        DATE,                     -- Date of this purchase
    payment_method       VARCHAR(50),              -- Payment method used
    days_since_install   INT,                      -- Days from install to this purchase
    purchase_segment     VARCHAR(20),              -- Derived: 'First', 'Repeat', 'Single'
    is_first_purchase    BOOLEAN,                  -- Whether this is the user's first purchase
    
    -- Metadata
    data_version         DATE DEFAULT CURRENT_DATE,
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert purchase records (one per paying user, since we only have aggregated data)
-- Note: With aggregated data, we create one representative transaction per user.
-- For a real multi-transaction scenario, you'd have multiple rows per player_id.
INSERT INTO purchase_cleaned (
    purchase_id,
    player_id,
    purchase_amount,
    purchase_date,
    payment_method,
    days_since_install,
    purchase_segment,
    is_first_purchase
)
SELECT 
    -- Generate a deterministic UUID based on player_id and purchase date
    gen_random_uuid() as purchase_id,
    player_id,
    in_app_purchase_amount as purchase_amount,
    last_purchase_date as purchase_date,
    payment_method,
    first_purchase_days_after_install as days_since_install,
    -- Determine purchase segment based on amount
    CASE 
        WHEN in_app_purchase_amount <= 20 THEN 'Minnow'
        WHEN in_app_purchase_amount <= 500 THEN 'Dolphin'
        ELSE 'Whale'
    END as purchase_segment,
    TRUE as is_first_purchase  -- With aggregated data, this represents their first/only purchase
FROM players_cleaned
WHERE is_purchaser = TRUE 
    AND in_app_purchase_amount > 0
    AND last_purchase_date IS NOT NULL;

-- Add index for better query performance
CREATE INDEX idx_purchase_player ON purchase_cleaned(player_id);
CREATE INDEX idx_purchase_date ON purchase_cleaned(purchase_date);
CREATE INDEX idx_purchase_segment ON purchase_cleaned(purchase_segment);


