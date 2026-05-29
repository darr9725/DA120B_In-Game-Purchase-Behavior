# Mobile Game In-App Purchase Data Cleaning & Usage Guide

This document explains how to transform the raw dataset `raw_data` into a clean, analysis-ready table `players_cleaned`. It also provides validation steps and example queries to kickstart your analysis of what drives players to make in-game purchases.

---

## 1. Overview

The raw data (`raw_data`) contains one row per player with demographic, behavioral, and monetization fields.  
However, it includes outliers, inconsistent formatting, and missing values that need to be cleaned before reliable analysis can be performed.

We will create a **clean table** (`players_cleaned`) that:
- Standardizes text fields (gender, country)
- Removes invalid age values and flags them
- Computes derived metrics (total play time, purchaser flag)
- Preserves the granularity of one row per player

---

## 2. Prerequisites

- You have a **PostgreSQL** database with the `raw_data` table already imported.
- All column names match exactly:
  - `userID` (UUID), `age` (NUMERIC), `gender` (VARCHAR(10)), `country` (VARCHAR(50)), `device` (VARCHAR(10)), `game_genre` (VARCHAR(50)), `session_count` (INT), `average_session_length` (REAL), `spending_segment` (VARCHAR(20)), `in_app_purchase_amount` (NUMERIC(10,2)), `first_purchase_days_after_install` (INT), `payment_method` (VARCHAR(50)), `last_purchase_date` (DATE).

---

## 3. Cleaned Table Structure

Run the following `CREATE TABLE` statement to set up the target table.

```sql
DROP TABLE IF EXISTS players_cleaned;

CREATE TABLE players_cleaned (
    player_id               UUID PRIMARY KEY,
    age                     INT,                        -- cleaned age (5–80 only)
    gender                  VARCHAR(10),                -- standardized gender
    country                 VARCHAR(50),                -- standardized country (uppercase)
    device                  VARCHAR(10),
    game_genre              VARCHAR(50),
    session_count           INT,
    avg_session_length      REAL,                       -- raw average session length
    total_play_mins         NUMERIC(10,2),              -- derived: session_count * avg_session_length
    spending_segment        VARCHAR(20),
    in_app_purchase_amount  NUMERIC(10,2),
    first_purchase_days_after_install INT,
    payment_method          VARCHAR(50),
    last_purchase_date      DATE,

    -- Derived analysis flags
    is_purchaser            BOOLEAN,                    -- TRUE if spent > 0
    days_to_first_pay       INT,                        -- same as first_purchase_days_after_install
    is_outlier_age          BOOLEAN DEFAULT FALSE,
    data_version            DATE DEFAULT CURRENT_DATE
);
```
---

## 4. Cleaning & Loading Data

Execute the `INSERT INTO ... SELECT ...` statement below. It performs all necessary transformations in one step.

```sql
INSERT INTO players_cleaned (
    player_id, age, gender, country, device, game_genre,
    session_count, avg_session_length, total_play_mins,
    spending_segment, in_app_purchase_amount,
    first_purchase_days_after_install, payment_method,
    last_purchase_date,
    is_purchaser, days_to_first_pay, is_outlier_age
)
SELECT
    userID,
    -- Age cleaning: keep 5-80, otherwise set to NULL and flag
    CASE WHEN age BETWEEN 5 AND 80 THEN age::INT ELSE NULL END,
    -- Gender standardization: Capitalize first letter, lower the rest, fill missing
    CASE
        WHEN TRIM(gender) = '' OR gender IS NULL THEN 'Unknown'
        ELSE CONCAT(UPPER(LEFT(TRIM(gender),1)), LOWER(SUBSTRING(TRIM(gender),2)))
    END,
    -- Country: uppercase and trim
    UPPER(TRIM(country)),
    device,
    game_genre,
    session_count,
    average_session_length,
    -- Total play time: cast to numeric to allow rounding to 2 decimals (PostgreSQL)
    ROUND((session_count * average_session_length)::numeric, 2),
    spending_segment,
    COALESCE(in_app_purchase_amount, 0.00),
    first_purchase_days_after_install,
    payment_method,
    last_purchase_date,
    -- Purchaser flag
    CASE WHEN COALESCE(in_app_purchase_amount, 0) > 0 THEN TRUE ELSE FALSE END,
    first_purchase_days_after_install,
    -- Outlier flag
    CASE WHEN age BETWEEN 5 AND 80 THEN FALSE ELSE TRUE END
FROM raw_data;
```

---

## 5. Validation Queries

After the insert, run these checks to ensure data integrity.

```sql
-- 1. Row count should match raw_data
SELECT COUNT(*) FROM players_cleaned;

-- 2. Purchaser split and average spend
SELECT 
    is_purchaser, 
    COUNT(*) AS player_count, 
    ROUND(AVG(in_app_purchase_amount), 2) AS avg_spent
FROM players_cleaned
GROUP BY is_purchaser;

-- 3. Age outlier check
SELECT is_outlier_age, COUNT(*) FROM players_cleaned GROUP BY is_outlier_age;

-- 4. Game genre distribution
SELECT game_genre, COUNT(*) FROM players_cleaned GROUP BY game_genre ORDER BY 2 DESC;

-- 5. Sample of cleaned rows
SELECT * FROM players_cleaned LIMIT 10;
```

---

## 6. How to Use the Cleaned Data for Analysis

Now you can directly investigate the drivers of in-game purchasing. Here are a few starter queries:

### 6.1 Compare playtime between payers and non-payers
```sql
SELECT 
    is_purchaser,
    AVG(total_play_mins) AS avg_total_mins,
    AVG(session_count) AS avg_sessions,
    AVG(avg_session_length) AS avg_session_len
FROM players_cleaned
GROUP BY is_purchaser;
```

### 6.2 Conversion rate by game genre
```sql
SELECT 
    game_genre,
    COUNT(*) AS total_players,
    SUM(CASE WHEN is_purchaser THEN 1 ELSE 0 END) AS payers,
    ROUND(100.0 * SUM(CASE WHEN is_purchaser THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate
FROM players_cleaned
GROUP BY game_genre
ORDER BY conversion_rate DESC;
```

### 6.3 Average days to first purchase by country
```sql
SELECT 
    country,
    AVG(first_purchase_days_after_install) AS avg_days_to_pay,
    COUNT(*) AS paying_users
FROM players_cleaned
WHERE is_purchaser
GROUP BY country
ORDER BY avg_days_to_pay;
```

### 6.4 Identify which session count range triggers first purchase
```sql
SELECT 
    CASE 
        WHEN first_purchase_days_after_install <= 1 THEN 'Day 0-1'
        WHEN first_purchase_days_after_install <= 7 THEN 'Day 2-7'
        WHEN first_purchase_days_after_install <= 30 THEN 'Day 8-30'
        ELSE '>30 days'
    END AS purchase_window,
    COUNT(*) AS user_count
FROM players_cleaned
WHERE is_purchaser
GROUP BY purchase_window
ORDER BY MIN(first_purchase_days_after_install);
```

---

## 7. Extending the Schema (Optional)

If you later obtain transaction‑level data (e.g., each purchase with item type and timestamp), you can create a second table `purchases_cleaned` and join it with `players_cleaned` on `player_id`. This will allow you to analyze:

- Which items are bought first
- Purchase timing relative to game progression
- The “magic moment” when a player decides to pay

The template for that table and its loading script can be provided upon request.

---

## 8. Important Notes

- Age outliers: Rows with `age` outside 5–80 are kept in the table (`age` set to `NULL`) but flagged with `is_outlier_age = TRUE`. You may exclude them in sensitive analyses using `WHERE is_outlier_age = FALSE`.
- Missing gender: Treated as `'Unknown'`. If you prefer to drop them, add `WHERE gender != 'Unknown'` in your queries.
- Total play time: Derived as `session_count * average_session_length`. If your `average_session_length` is stored in seconds instead of minutes, convert it accordingly (e.g., divide by 60) in the loading script.
- PostgreSQL compatibility: The provided code uses `::numeric` and standard SQL functions. For other DBMS, adjust the round/cast syntax as needed.
