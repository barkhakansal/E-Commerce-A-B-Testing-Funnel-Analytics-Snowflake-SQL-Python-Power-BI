-- Create the main database for the ecommerce data pipeline
CREATE DATABASE ECOMMERCE_DB;

-- Create schemas following the medallion architecture (Bronze, Silver, Gold)
CREATE SCHEMA BRONZE;
CREATE SCHEMA SILVER;
CREATE SCHEMA GOLD;

-- Define a CSV file format for ingesting raw data files
CREATE OR REPLACE FILE FORMAT ECOMMERCE_DB.BRONZE.CSV_FORMAT
TYPE = 'CSV'
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY = '"'
NULL_IF = ('', 'NULL', 'NaN');

-- Create an internal stage for loading ecommerce data files
CREATE OR REPLACE STAGE ECOMMERCE_DB.BRONZE.ECOM_STAGE
FILE_FORMAT = ECOMMERCE_DB.BRONZE.CSV_FORMAT;

-- Verify files uploaded to the stage
LIST @ECOMMERCE_DB.BRONZE.ECOM_STAGE;

-- Raw campaigns table storing marketing campaign metadata for A/B testing
CREATE OR REPLACE TABLE ECOMMERCE_DB.BRONZE.CAMPAIGNS_RAW (
    campaign_id INT,
    channel STRING,
    objective STRING,
    start_date DATE,
    end_date DATE,
    target_segment STRING,
    expected_uplift FLOAT
);

-- Raw customers table capturing customer demographics and acquisition details
CREATE OR REPLACE TABLE ECOMMERCE_DB.BRONZE.CUSTOMERS_RAW (
    customer_id INT,
    signup_date DATE,
    country STRING,
    age INT,
    gender STRING,
    loyalty_tier STRING,
    acquisition_channel STRING
);

-- Raw events table tracking customer interactions, sessions, and experiment assignments
CREATE OR REPLACE TABLE ECOMMERCE_DB.BRONZE.EVENTS_RAW (
    event_id INT,
    timestamp TIMESTAMP,
    customer_id INT,
    session_id INT,
    event_type STRING,
    product_id INT,
    device_type STRING,
    traffic_source STRING,
    campaign_id INT,
    page_category STRING,
    session_duration_seconds FLOAT,
    experiment_group STRING
);

-- Raw products table containing product catalog details and pricing
CREATE OR REPLACE TABLE ECOMMERCE_DB.BRONZE.PRODUCTS_RAW (
    product_id INT,
    category STRING,
    brand STRING,
    base_price FLOAT,
    launch_date DATE,
    is_premium INT
);

-- Raw transactions table recording purchases, discounts, and refunds
CREATE OR REPLACE TABLE ECOMMERCE_DB.BRONZE.TRANSACTIONS_RAW (
    transaction_id INT,
    timestamp TIMESTAMP,
    customer_id INT,
    product_id INT,
    quantity INT,
    discount_applied FLOAT,
    gross_revenue FLOAT,
    campaign_id INT,
    refund_flag INT
);

-- Load campaigns data from stage into bronze table
COPY INTO ECOMMERCE_DB.BRONZE.CAMPAIGNS_RAW
FROM @ECOMMERCE_DB.BRONZE.ECOM_STAGE/campaigns.csv
FILE_FORMAT = (FORMAT_NAME = ECOMMERCE_DB.BRONZE.CSV_FORMAT)
ON_ERROR = 'CONTINUE';


-- Load customers data from stage into bronze table
COPY INTO ECOMMERCE_DB.BRONZE.CUSTOMERS_RAW
FROM @ECOMMERCE_DB.BRONZE.ECOM_STAGE/customers.csv
FILE_FORMAT = (FORMAT_NAME = ECOMMERCE_DB.BRONZE.CSV_FORMAT)
ON_ERROR = 'CONTINUE';

-- Load events data from stage into bronze table
COPY INTO ECOMMERCE_DB.BRONZE.EVENTS_RAW
FROM @ECOMMERCE_DB.BRONZE.ECOM_STAGE/events.csv
FILE_FORMAT = (FORMAT_NAME = ECOMMERCE_DB.BRONZE.CSV_FORMAT)
ON_ERROR = 'CONTINUE';

-- Load products data from stage into bronze table
COPY INTO ECOMMERCE_DB.BRONZE.PRODUCTS_RAW
FROM @ECOMMERCE_DB.BRONZE.ECOM_STAGE/products.csv
FILE_FORMAT = (FORMAT_NAME = ECOMMERCE_DB.BRONZE.CSV_FORMAT)
ON_ERROR = 'CONTINUE';

-- Load transactions data from stage into bronze table
COPY INTO ECOMMERCE_DB.BRONZE.TRANSACTIONS_RAW
FROM @ECOMMERCE_DB.BRONZE.ECOM_STAGE/transactions.csv
FILE_FORMAT = (FORMAT_NAME = ECOMMERCE_DB.BRONZE.CSV_FORMAT)
ON_ERROR = 'CONTINUE';

-- Validate row count of ingested events data
SELECT COUNT(*) FROM ECOMMERCE_DB.BRONZE.EVENTS_RAW;

-- Preview sample rows from the events table
SELECT *
FROM ECOMMERCE_DB.BRONZE.EVENTS_RAW
LIMIT 10;

-- Clean campaigns: deduplicate, trim strings, and filter out invalid date ranges
CREATE OR REPLACE TABLE ECOMMERCE_DB.SILVER.CAMPAIGNS_CLEAN AS
SELECT DISTINCT
    campaign_id,
    TRIM(channel) AS channel,
    TRIM(objective) AS objective,
    start_date,
    end_date,
    TRIM(target_segment) AS target_segment,
    expected_uplift
FROM ECOMMERCE_DB.BRONZE.CAMPAIGNS_RAW
WHERE campaign_id IS NOT NULL
AND start_date <= end_date;

-- Clean customers: deduplicate, normalize text casing, and filter valid ages
  CREATE OR REPLACE TABLE ECOMMERCE_DB.SILVER.CUSTOMERS_CLEAN AS
SELECT DISTINCT
    customer_id,
    signup_date,
    UPPER(TRIM(country)) AS country,
    age,
    INITCAP(TRIM(gender)) AS gender,
    INITCAP(TRIM(loyalty_tier)) AS loyalty_tier,
    INITCAP(TRIM(acquisition_channel)) AS acquisition_channel
FROM ECOMMERCE_DB.BRONZE.CUSTOMERS_RAW
WHERE customer_id IS NOT NULL
  AND age BETWEEN 18 AND 100;

-- Clean products: deduplicate, normalize text, and filter valid prices and flags
  CREATE OR REPLACE TABLE ECOMMERCE_DB.SILVER.PRODUCTS_CLEAN AS
SELECT DISTINCT
    product_id,
    INITCAP(TRIM(category)) AS category,
    TRIM(brand) AS brand,
    base_price,
    launch_date,
    is_premium
FROM ECOMMERCE_DB.BRONZE.PRODUCTS_RAW
WHERE product_id IS NOT NULL
  AND base_price > 0
  AND is_premium IN (0, 1);

-- Clean events: deduplicate, normalize text, and filter valid event types and durations
  CREATE OR REPLACE TABLE ECOMMERCE_DB.SILVER.EVENTS_CLEAN AS
SELECT DISTINCT
    event_id,
    timestamp,
    customer_id,
    session_id,
    LOWER(TRIM(event_type)) AS event_type,
    product_id,
    LOWER(TRIM(device_type)) AS device_type,
    INITCAP(TRIM(traffic_source)) AS traffic_source,
    campaign_id,
    INITCAP(TRIM(page_category)) AS page_category,
    session_duration_seconds,
    TRIM(experiment_group) AS experiment_group
FROM ECOMMERCE_DB.BRONZE.EVENTS_RAW
WHERE event_id IS NOT NULL
  AND customer_id IS NOT NULL
  AND session_id IS NOT NULL
  AND event_type IN ('view', 'click', 'add_to_cart', 'purchase', 'bounce')
  AND session_duration_seconds >= 0;

-- Clean transactions: deduplicate and filter valid quantities, discounts, and refund flags
  CREATE OR REPLACE TABLE ECOMMERCE_DB.SILVER.TRANSACTIONS_CLEAN AS
SELECT DISTINCT
    transaction_id,
    timestamp,
    customer_id,
    product_id,
    quantity,
    discount_applied,
    gross_revenue,
    campaign_id,
    refund_flag
FROM ECOMMERCE_DB.BRONZE.TRANSACTIONS_RAW
WHERE transaction_id IS NOT NULL
  AND customer_id IS NOT NULL
  AND product_id IS NOT NULL
  AND quantity > 0
  AND discount_applied BETWEEN 0 AND 0.20
  AND refund_flag IN (0, 1);

  
-- Validate row counts across all Silver layer tables
SELECT 'campaigns' AS table_name, COUNT(*) AS rows_count FROM ECOMMERCE_DB.SILVER.CAMPAIGNS_CLEAN
UNION ALL
SELECT 'customers', COUNT(*) FROM ECOMMERCE_DB.SILVER.CUSTOMERS_CLEAN
UNION ALL
SELECT 'products', COUNT(*) FROM ECOMMERCE_DB.SILVER.PRODUCTS_CLEAN
UNION ALL
SELECT 'events', COUNT(*) FROM ECOMMERCE_DB.SILVER.EVENTS_CLEAN
UNION ALL
SELECT 'transactions', COUNT(*) FROM ECOMMERCE_DB.SILVER.TRANSACTIONS_CLEAN;

-- Check experiment group distribution for A/B test balance
SELECT experiment_group, COUNT(*) AS rows_count
FROM ECOMMERCE_DB.SILVER.EVENTS_CLEAN
GROUP BY experiment_group;

-- Summarize event type distribution
SELECT event_type, COUNT(*) AS event_count
FROM ECOMMERCE_DB.SILVER.EVENTS_CLEAN
GROUP BY event_type
ORDER BY event_count DESC;

-- ----------------------Create gold tables---------------------------
-- Creates one row per customer and marks whether they purchased.
 CREATE OR REPLACE TABLE ECOMMERCE_DB.GOLD.USER_CONVERSIONS AS
SELECT
    customer_id,
    MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS converted,
    MIN(timestamp) AS first_event_time,
    MAX(timestamp) AS last_event_time,
    COUNT(*) AS total_events,
    COUNT(DISTINCT session_id) AS total_sessions
FROM ECOMMERCE_DB.SILVER.EVENTS_CLEAN
GROUP BY customer_id;

select * from ECOMMERCE_DB.GOLD.USER_CONVERSIONS limit 5;

CREATE OR REPLACE TABLE ECOMMERCE_DB.GOLD.USER_EXPERIMENT_GROUP AS
SELECT
    customer_id,
    experiment_group
FROM (
    SELECT
        customer_id,
        experiment_group,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY timestamp
        ) AS rn
    FROM ECOMMERCE_DB.SILVER.EVENTS_CLEAN
)
WHERE rn = 1;

select * from ECOMMERCE_DB.GOLD.USER_EXPERIMENT_GROUP limit 5;

select * from ECOMMERCE_DB.GOLD.USER_EXPERIMENT_GROUP

-- Compares Control vs Variant_A vs Variant_B.
CREATE OR REPLACE TABLE ECOMMERCE_DB.GOLD.EXPERIMENT_PERFORMANCE AS
SELECT
    ueg.experiment_group,
    COUNT(DISTINCT ueg.customer_id) AS users,

    COUNT(DISTINCT CASE
        WHEN e.event_type = 'purchase'
        THEN ueg.customer_id
    END) AS converted_users,

    ROUND(
        COUNT(DISTINCT CASE
            WHEN e.event_type = 'purchase'
            THEN ueg.customer_id
        END) * 100.0
        / COUNT(DISTINCT ueg.customer_id),
        2
    ) AS conversion_rate_pct

FROM ECOMMERCE_DB.GOLD.USER_EXPERIMENT_GROUP ueg
LEFT JOIN ECOMMERCE_DB.SILVER.EVENTS_CLEAN e
ON ueg.customer_id = e.customer_id
GROUP BY ueg.experiment_group;


select * from ECOMMERCE_DB.GOLD.EXPERIMENT_PERFORMANCE limit 5;

-- Shows how users move through view → click → cart → purchase.
CREATE OR REPLACE TABLE ECOMMERCE_DB.GOLD.FUNNEL_ANALYSIS AS
SELECT
    experiment_group,
    COUNT(DISTINCT CASE WHEN event_type = 'view' THEN customer_id END) AS viewed_users,
    COUNT(DISTINCT CASE WHEN event_type = 'click' THEN customer_id END) AS clicked_users,
    COUNT(DISTINCT CASE WHEN event_type = 'add_to_cart' THEN customer_id END) AS cart_users,
    COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN customer_id END) AS purchased_users
FROM ECOMMERCE_DB.SILVER.EVENTS_CLEAN
GROUP BY experiment_group;

select * from ECOMMERCE_DB.GOLD.FUNNEL_ANALYSIS limit 5;

-- Funnel conversion rates
CREATE OR REPLACE TABLE ECOMMERCE_DB.GOLD.FUNNEL_RATES AS
SELECT
    experiment_group,
    viewed_users,
    clicked_users,
    cart_users,
    purchased_users,
    ROUND(clicked_users * 100.0 / NULLIF(viewed_users, 0), 2) AS view_to_click_pct,
    ROUND(cart_users * 100.0 / NULLIF(clicked_users, 0), 2) AS click_to_cart_pct,
    ROUND(purchased_users * 100.0 / NULLIF(cart_users, 0), 2) AS cart_to_purchase_pct,
    ROUND(purchased_users * 100.0 / NULLIF(viewed_users, 0), 2) AS overall_funnel_conversion_pct
FROM ECOMMERCE_DB.GOLD.FUNNEL_ANALYSIS;

select * from ECOMMERCE_DB.GOLD.FUNNEL_RATES limit 5;

-- Revenue by experiment group
CREATE OR REPLACE TABLE ECOMMERCE_DB.GOLD.EXPERIMENT_REVENUE AS
SELECT
    ueg.experiment_group,
    COUNT(DISTINCT ueg.customer_id) AS users,
    COUNT(DISTINCT t.transaction_id) AS transactions,
    ROUND(SUM(t.gross_revenue), 2) AS total_revenue,
    ROUND(
        SUM(t.gross_revenue) / NULLIF(COUNT(DISTINCT ueg.customer_id), 0),
        2
    ) AS revenue_per_user
FROM ECOMMERCE_DB.GOLD.USER_EXPERIMENT_GROUP ueg
LEFT JOIN ECOMMERCE_DB.SILVER.TRANSACTIONS_CLEAN t
    ON ueg.customer_id = t.customer_id
GROUP BY ueg.experiment_group;

select * from ECOMMERCE_DB.GOLD.EXPERIMENT_REVENUE limit 5;

-- Campaign performance
CREATE OR REPLACE TABLE ECOMMERCE_DB.GOLD.CAMPAIGN_PERFORMANCE AS
WITH event_summary AS (
    SELECT
        campaign_id,
        COUNT(DISTINCT customer_id) AS users_reached,
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN customer_id END) AS converted_users
    FROM ECOMMERCE_DB.SILVER.EVENTS_CLEAN
    WHERE campaign_id <> 0
    GROUP BY campaign_id
),

transaction_summary AS (
    SELECT
        campaign_id,
        COUNT(DISTINCT transaction_id) AS transactions,
        ROUND(SUM(gross_revenue), 2) AS total_revenue
    FROM ECOMMERCE_DB.SILVER.TRANSACTIONS_CLEAN
    WHERE campaign_id <> 0
    GROUP BY campaign_id
)

SELECT
    c.campaign_id,
    c.channel,
    c.objective,
    c.target_segment,
    c.expected_uplift,

    COALESCE(e.users_reached, 0) AS users_reached,
    COALESCE(e.converted_users, 0) AS converted_users,

    ROUND(
        COALESCE(e.converted_users, 0) * 100.0
        / NULLIF(COALESCE(e.users_reached, 0), 0),
        2
    ) AS conversion_rate_pct,

    COALESCE(t.transactions, 0) AS transactions,
    COALESCE(t.total_revenue, 0) AS total_revenue

FROM ECOMMERCE_DB.SILVER.CAMPAIGNS_CLEAN c
LEFT JOIN event_summary e
    ON c.campaign_id = e.campaign_id
LEFT JOIN transaction_summary t
    ON c.campaign_id = t.campaign_id;

    select * from ECOMMERCE_DB.GOLD.CAMPAIGN_PERFORMANCE limit 5;

    -- Segment performance. Compares conversion by device, traffic source, and experiment group.
    CREATE OR REPLACE TABLE ECOMMERCE_DB.GOLD.SEGMENT_PERFORMANCE AS
SELECT
    experiment_group,
    device_type,
    traffic_source,
    COUNT(DISTINCT customer_id) AS users,
    COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN customer_id END) AS converted_users,
    ROUND(
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN customer_id END) * 100.0
        / NULLIF(COUNT(DISTINCT customer_id), 0),
        2
    ) AS conversion_rate_pct
FROM ECOMMERCE_DB.SILVER.EVENTS_CLEAN
GROUP BY experiment_group, device_type, traffic_source;

select * from ECOMMERCE_DB.GOLD.SEGMENT_PERFORMANCE limit 5;


select * from ECOMMERCE_DB.GOLD.USER_EXPERIMENT_GROUP order by customer_id limit 5;

-- Final dashboard table. This combines experiment, conversion, and revenue.
CREATE OR REPLACE TABLE ECOMMERCE_DB.GOLD.EXPERIMENT_DASHBOARD AS
SELECT
    ep.experiment_group,
    ep.users,
    ep.converted_users,
    ep.conversion_rate_pct,
    er.transactions,
    er.total_revenue,
    er.revenue_per_user,
    fr.viewed_users,
    fr.clicked_users,
    fr.cart_users,
    fr.purchased_users,
    fr.view_to_click_pct,
    fr.click_to_cart_pct,
    fr.cart_to_purchase_pct,
    fr.overall_funnel_conversion_pct
FROM ECOMMERCE_DB.GOLD.EXPERIMENT_PERFORMANCE ep
LEFT JOIN ECOMMERCE_DB.GOLD.EXPERIMENT_REVENUE er
    ON ep.experiment_group = er.experiment_group
LEFT JOIN ECOMMERCE_DB.GOLD.FUNNEL_RATES fr
    ON ep.experiment_group = fr.experiment_group;


------------------------------------- A/B Testing ------------------------------------------
SELECT
    experiment_group,
    COUNT(DISTINCT customer_id) AS users
FROM ECOMMERCE_DB.GOLD.USER_EXPERIMENT_GROUP
GROUP BY experiment_group
ORDER BY users DESC;

-- Calculate conversion rate
SELECT *
FROM ECOMMERCE_DB.GOLD.EXPERIMENT_PERFORMANCE;

-- Calculate lift vs control
WITH control AS (
    SELECT conversion_rate_pct AS control_rate
    FROM ECOMMERCE_DB.GOLD.EXPERIMENT_PERFORMANCE
    WHERE experiment_group = 'Control'
)

SELECT
    e.experiment_group,
    e.users,
    e.converted_users,
    e.conversion_rate_pct,

    ROUND(
        e.conversion_rate_pct - c.control_rate,
        2
    ) AS absolute_lift_pct_points,

    ROUND(
        (e.conversion_rate_pct - c.control_rate)
        / c.control_rate * 100,
        2
    ) AS relative_lift_pct

FROM ECOMMERCE_DB.GOLD.EXPERIMENT_PERFORMANCE e
CROSS JOIN control c
ORDER BY conversion_rate_pct DESC;

-- Funnel comparision
SELECT *
FROM ECOMMERCE_DB.GOLD.FUNNEL_RATES;

-- Revenue Comparision
SELECT *
FROM ECOMMERCE_DB.GOLD.EXPERIMENT_REVENUE
ORDER BY revenue_per_user DESC;

-- Segment analysis
SELECT *
FROM ECOMMERCE_DB.GOLD.SEGMENT_PERFORMANCE
ORDER BY conversion_rate_pct DESC;